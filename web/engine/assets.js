// 资源加载：场景 JSON、网格二进制、贴图（PNG 或原始像素）。全部按 URL 缓存。
import { ATTRIBS } from './shaderlab.js';

// 海外版放在 Cloudflare Pages，单个文件不能超过 25 MB：超大的网格（如 GrassField）那边只放 .gz。
// 取原文件 404 时改取 .gz，在浏览器里解压（国内服务器上原文件都在，不走这里）。
async function fetchBig(url) {
  const r = await fetch(url);
  if (r.status !== 404 || typeof DecompressionStream === 'undefined') return r;
  const g = await fetch(url + '.gz');
  if (!g.ok) return r;
  const buf = new Uint8Array(await g.arrayBuffer());
  if (buf[0] !== 0x1f || buf[1] !== 0x8b) return new Response(buf);          // 已被解过压
  return new Response(new Blob([buf]).stream().pipeThrough(new DecompressionStream('gzip')));
}

export class Assets {
  constructor(glc, base) {
    this.glc = glc;
    this.gl = glc.gl;
    // 转成绝对地址：动态 import() 按模块自身位置解析相对路径，必须给绝对 URL
    this.base = new URL(base.endsWith('/') ? base : base + '/', location.href).href;
    this.cache = new Map();
    this.texIndex = null;
  }

  url(p) { return this.base + p; }

  once(key, fn) {
    if (!this.cache.has(key)) this.cache.set(key, fn().catch((e) => { this.cache.delete(key); throw e; }));
    return this.cache.get(key);
  }

  json(p) { return this.once('json:' + p, async () => { const r = await fetch(this.url(p)); if (!r.ok) throw new Error(`加载失败 ${p}（${r.status}）`); return r.json(); }); }
  text(p) { return this.once('text:' + p, async () => { const r = await fetch(this.url(p)); if (!r.ok) throw new Error(`加载失败 ${p}（${r.status}）`); return r.text(); }); }
  async bin(p) {
    return this.once('bin:' + p, async () => {
      const r = await fetchBig(this.url(p));
      if (!r.ok) throw new Error(`加载失败 ${p}（${r.status}）`);
      const buf = await r.arrayBuffer();
      const hl = new DataView(buf).getUint32(0, true);
      const header = JSON.parse(new TextDecoder().decode(new Uint8Array(buf, 4, hl)));
      return { header, body: buf.slice(4 + hl) };
    });
  }

  scene(id) { return this.json(`data/scenes/${id}.json`); }

  // ---------------- 网格 ----------------
  mesh(key) {
    return this.once('mesh:' + key, async () => {
      const { header, body } = await this.bin(`data/meshes/${key}.bin`);
      return this.uploadMesh(header, body);
    });
  }

  // 也可以直接从 JS 数组建网格（章节脚本生成的网格）
  uploadMesh(header, body) {
    const gl = this.gl;
    const vao = gl.createVertexArray();
    gl.bindVertexArray(vao);
    const buffers = [];
    const cpu = {};
    for (const [name, a] of Object.entries(header.attributes)) {
      const loc = { position: ATTRIBS.positionOS, normal: ATTRIBS.normalOS, tangent: ATTRIBS.tangentOS, color: ATTRIBS.color, uv0: ATTRIBS.texcoord0, uv1: ATTRIBS.texcoord1, uv2: ATTRIBS.texcoord2, uv3: ATTRIBS.texcoord3 }[name];
      if (loc === undefined) continue;
      const data = new Float32Array(body, a.offset, header.vertexCount * a.comps);
      cpu[name] = data;
      const b = gl.createBuffer();
      gl.bindBuffer(gl.ARRAY_BUFFER, b);
      gl.bufferData(gl.ARRAY_BUFFER, data, gl.STATIC_DRAW);
      gl.enableVertexAttribArray(loc);
      gl.vertexAttribPointer(loc, a.comps, gl.FLOAT, false, 0, 0);
      buffers.push(b);
    }
    // 没有的属性给默认值：颜色白、切线 (1,0,0,1)
    if (!header.attributes.color) gl.vertexAttrib4f(ATTRIBS.color, 1, 1, 1, 1);
    if (!header.attributes.tangent) gl.vertexAttrib4f(ATTRIBS.tangentOS, 1, 0, 0, 1);
    const indices = new Uint32Array(body, header.indexOffset, header.indexCount);
    const ib = gl.createBuffer();
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, ib);
    gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, indices, gl.STATIC_DRAW);
    gl.bindVertexArray(null);
    return { vao, buffers, ib, header, subMeshes: header.subMeshes, bounds: header.bounds, cpu, indices };
  }

  // ---------------- 贴图 ----------------
  async textureMeta(key) {
    if (!this.texIndex) this.texIndex = await this.json('data/textures/index.json');
    return this.texIndex[key];
  }

  texture(key) {
    return this.once('tex:' + key, async () => {
      const meta = await this.textureMeta(key);
      if (!meta) throw new Error('贴图索引里没有 ' + key);
      const o = { wrapU: meta.wrapU, wrapV: meta.wrapV, filter: meta.filter, aniso: meta.aniso, srgb: !!meta.srgb };
      if (meta.format === 'image') {
        const r = await fetch(this.url('data/textures/' + key));
        const blob = await r.blob();
        const img = await createImageBitmap(blob, { imageOrientation: 'flipY', premultiplyAlpha: 'none', colorSpaceConversion: 'none' });
        const t = this.glc.textureFromImage(img, { ...o, mips: meta.mips !== 1 });
        t.meta = meta;
        return t;
      }
      if (meta.format === 'float32' || meta.format === 'rgba8') {
        const { body } = await this.bin(`data/textures/${key}.bin`);
        const isF = meta.format === 'float32';
        const fmt = isF ? 'RGBA16F_FROM32' : meta.srgb ? 'SRGB8_ALPHA8' : 'RGBA8';
        const lv = meta.levels.map((l) => ({ ...l, data: isF ? new Float32Array(body, l.offset, l.w * l.h * 4) : new Uint8Array(body, l.offset, l.w * l.h * 4) }));
        let t;
        if (meta.dim === 'Cube') t = this.glc.textureCube(meta.width, fmt, lv, o);
        else if (meta.dim === 'Tex3D') t = this.glc.texture3D(meta.width, meta.height, meta.depth3d, fmt, lv[0].data, o);
        else t = this.glc.texture2D(meta.width, meta.height, fmt, lv[0].data, { ...o, mips: lv.length > 1, levels: lv.length > 1 ? lv : null });
        t.meta = meta;
        return t;
      }
      // RenderTexture 等运行时才有内容的贴图：给个占位，由章节脚本填充
      const t = meta.dim === 'Cube' ? this.glc.defaults.cube : this.glc.defaults.black;
      return { ...t, meta, placeholder: true };
    });
  }
}
