// 浏览器里的“迷你 URP”：按 URP 14 Forward 渲染器的顺序画一帧。
//   主光源阴影 → 附加光源阴影 → 不透明物体 → 拷贝深度 → 天空盒 → 拷贝颜色(_CameraOpaqueTexture)
//   → 半透明物体 → 后处理 → 输出到画布
// Renderer Feature 的 Pass 按 RenderPassEvent 插进这些步骤之间（见 features.js）。
import { GLContext, setUniform } from './gl.js';
import { Assets } from './assets.js';
import { ShaderLibrary, Material } from './shader.js';
import { mat4, vec3 } from './math.js';
import { PostProcess } from './post.js';
import { loadFeature, RenderPassEvent, layerMask } from './features.js';
import { loadBehaviour } from './behaviours.js';

const OPAQUE_PASSES = ['SRPDefaultUnlit', 'UniversalForward', 'UniversalForwardOnly'];

export class Engine {
  constructor(canvas, { base = './', preserveDrawingBuffer = false } = {}) {
    this.glc = new GLContext(canvas, { preserveDrawingBuffer });
    this.gl = this.glc.gl;
    this.canvas = canvas;
    this.assets = new Assets(this.glc, base);
    this.shaders = new ShaderLibrary(this.glc, this.assets);
    this.globals = new Map();
    this.errors = [];
    this.rtCache = new Map();
    this.onError = null;
  }

  async init() {
    await this.shaders.init();
    this.blitShader = await this.shaders.get('Hidden/Cookbook/Blit');
    this.blitMat = new Material(this.blitShader);
    this.commonShader = await this.shaders.get('Cookbook/Common');
    this.post = new PostProcess(this);
    await this.post.init();
    // 全屏三角形
    const gl = this.gl;
    this.fullscreenVAO = gl.createVertexArray();
    // 天空盒用的单位立方体
    this.skyCube = this.assets.uploadMesh(...cubeMesh());
  }

  setGlobal(name, v) { this.globals.set(name, v); }

  // ---------------- 场景 ----------------
  async loadScene(doc, panelIndex = 0, { onProgress } = {}) {
    const P = doc.panels[Math.min(panelIndex, doc.panels.length - 1)];
    const scene = new Scene(this, doc, P, panelIndex);
    await scene.load(onProgress);
    return scene;
  }

  material(json) { return new Material(this.shaders.getLoaded(json.shader), json); }

  // ---------------- 渲染目标池 ----------------
  rt(key, w, h, opts) {
    const k = `${key}|${w}x${h}|${JSON.stringify(opts)}`;
    let rt = this.rtCache.get(k);
    if (!rt) {
      for (const [kk, old] of this.rtCache) if (kk.startsWith(key + '|')) { this.glc.deleteRT(old); this.rtCache.delete(kk); }
      rt = this.glc.renderTarget(w, h, opts);
      this.rtCache.set(k, rt);
    }
    return rt;
  }

  bindTarget(rt) {
    const gl = this.gl;
    if (!rt || rt === 'screen') {
      gl.bindFramebuffer(gl.FRAMEBUFFER, null);
      gl.viewport(0, 0, this.canvas.width, this.canvas.height);
      this.currentTarget = null;
    } else {
      gl.bindFramebuffer(gl.FRAMEBUFFER, rt.fbo);
      gl.viewport(0, 0, rt.w, rt.h);
      this.currentTarget = rt;
    }
  }

  // ---------------- 渲染状态 ----------------
  applyState(state, mat, flip = false) {
    const gl = this.gl;
    const val = (v, def) => (v === undefined ? def : typeof v === 'object' && v.prop ? (mat ? mat.getFloat(v.prop) : def) : v);
    // 剔除：Unity 网格以顺时针为正面
    const cull = val(state.cull, 'Back');
    const cullMode = typeof cull === 'number' ? ['Off', 'Front', 'Back'][cull] : cull;
    if (cullMode === 'Off') gl.disable(gl.CULL_FACE);
    else { gl.enable(gl.CULL_FACE); gl.cullFace(cullMode === 'Front' ? gl.FRONT : gl.BACK); }
    gl.frontFace(flip ? gl.CCW : gl.CW);
    // 深度
    const zw = val(state.zwrite, 'On');
    gl.depthMask(zw === 'On' || zw === 1 || zw === 'True');
    const zt = val(state.ztest, 'LEqual');
    const ztName = typeof zt === 'number' ? ['Disabled', 'Never', 'Less', 'Equal', 'LEqual', 'Greater', 'NotEqual', 'GEqual', 'Always'][zt] : zt;
    if (ztName === 'Disabled' || ztName === 'Off') { gl.enable(gl.DEPTH_TEST); gl.depthFunc(gl.ALWAYS); }
    else { gl.enable(gl.DEPTH_TEST); gl.depthFunc(cmpFunc(gl, ztName)); }
    // 混合
    const b = state.blend;
    if (!b || b.length === 0 || val(b[0]) === 'Off') gl.disable(gl.BLEND);
    else {
      const f = b.map((x) => blendFactor(gl, val(x, 'One')));
      gl.enable(gl.BLEND);
      if (f.length >= 4) gl.blendFuncSeparate(f[0], f[1], f[2], f[3]);
      else gl.blendFunc(f[0], f[1]);
      if (f.some((x) => x === undefined)) gl.disable(gl.BLEND);
    }
    const op = state.blendOp;
    if (op && op.length) { const o = op.map((x) => blendOp(gl, val(x, 'Add'))); o.length > 1 ? gl.blendEquationSeparate(o[0], o[1]) : gl.blendEquation(o[0]); }
    else gl.blendEquation(gl.FUNC_ADD);
    // 颜色写入
    const cm = val(state.colorMask, 'RGBA');
    if (typeof cm === 'number') gl.colorMask(!!(cm & 8), !!(cm & 4), !!(cm & 2), !!(cm & 1));
    else { const s = String(cm); gl.colorMask(s.includes('R'), s.includes('G'), s.includes('B'), s.includes('A')); }
    // Alpha to Coverage（AlphaToMask On）：片元 alpha 转成 MSAA 覆盖掩码，只在多重采样目标上有效
    const a2c = val(state.alphaToMask, 'Off');
    if (a2c === 'On' || a2c === 'True' || +a2c > 0) gl.enable(gl.SAMPLE_ALPHA_TO_COVERAGE); else gl.disable(gl.SAMPLE_ALPHA_TO_COVERAGE);
    // 深度偏移
    if (state.offset) { gl.enable(gl.POLYGON_OFFSET_FILL); gl.polygonOffset(+val(state.offset[0], 0), +val(state.offset[1], 0)); }
    else gl.disable(gl.POLYGON_OFFSET_FILL);
    // 模板
    const st = state.stencil;
    if (st) {
      gl.enable(gl.STENCIL_TEST);
      const ref = +val(st.Ref, 0), rm = +val(st.ReadMask, 255), wm = +val(st.WriteMask, 255);
      const comp = val(st.Comp, 'Always'), pass = val(st.Pass, 'Keep'), fail = val(st.Fail, 'Keep'), zfail = val(st.ZFail, 'Keep');
      gl.stencilFunc(cmpFunc(gl, typeof comp === 'number' ? ['Disabled', 'Never', 'Less', 'Equal', 'LEqual', 'Greater', 'NotEqual', 'GEqual', 'Always'][comp] : comp), ref, rm);
      gl.stencilOp(stencilOp(gl, fail), stencilOp(gl, zfail), stencilOp(gl, pass));
      gl.stencilMask(wm);
    } else gl.disable(gl.STENCIL_TEST);
  }

  // ---------------- 画一个物体的一个 Pass ----------------
  // overrides：额外的 uniform（Map 或对象），优先级最高
  draw(obj, subIndex, mat, pass, { overrides = null, keywords = null, state = null } = {}) {
    const gl = this.gl;
    let prog;
    try {
      prog = mat.shader.program(pass, keywords || mat.keywords);
    } catch (e) {
      this.reportError(e);
      return;
    }
    gl.useProgram(prog.program);
    this.applyState(state || pass.state, mat, obj.flip);
    this.setUniforms(prog, mat, obj, overrides);
    const mesh = obj.mesh;
    gl.bindVertexArray(mesh.vao);
    const sm = mesh.subMeshes[Math.min(subIndex, mesh.subMeshes.length - 1)];
    const mode = sm.topology === 'Lines' ? gl.LINES : sm.topology === 'LineStrip' ? gl.LINE_STRIP : sm.topology === 'Points' ? gl.POINTS : gl.TRIANGLES;
    if (obj.instanceCount > 1) gl.drawElementsInstanced(mode, sm.count, gl.UNSIGNED_INT, sm.start * 4, obj.instanceCount);
    else gl.drawElements(mode, sm.count, gl.UNSIGNED_INT, sm.start * 4);
  }

  setUniforms(prog, mat, obj, overrides) {
    const gl = this.gl;
    const get = (name) => {
      if (overrides) { const v = overrides instanceof Map ? overrides.get(name) : overrides[name]; if (v !== undefined) return v; }
      if (obj) {
        if (name === 'unity_ObjectToWorld') return obj.matrix;
        if (name === 'unity_WorldToObject') return obj.invMatrix;
        if (name === 'unity_WorldTransformParams') return [0, 0, 0, obj.flip ? -1 : 1];
        if (obj.uniforms && obj.uniforms[name] !== undefined) return obj.uniforms[name];
      }
      if (mat) {
        const v = mat.props.get(name);
        if (v !== undefined) return v;
        if (name.endsWith('_ST')) { const t = mat.props.get(name.slice(0, -3)); if (t && t.st) return t.st; }
        if (name.endsWith('_TexelSize')) {
          const t = mat.props.get(name.slice(0, -10));
          const g = t && t.glTexture;
          if (g) return [1 / g.width, 1 / g.height, g.width, g.height];
        }
        if (name.endsWith('_HDR') && mat.props.has(name.slice(0, -4))) return [1, 1, 0, 0];
      }
      return this.globals.get(name);
    };
    for (const u of prog.uniforms.values()) {
      let v = get(u.name);
      if (u.unit !== undefined) {
        let tex = v && (v.glTexture || (v.tex ? v : null));
        if (!tex || tex.placeholder) tex = this.defaultTextureFor(u, v);
        gl.activeTexture(gl.TEXTURE0 + u.unit);
        gl.bindTexture(tex.target, tex.tex);
        gl.uniform1i(u.loc, u.unit);
        continue;
      }
      if (v === undefined || v === null) continue;
      if (typeof v === 'object' && !Array.isArray(v) && !(v instanceof Float32Array)) continue;
      if (typeof v === 'boolean') v = v ? 1 : 0;
      setUniform(gl, u, v);
    }
  }

  defaultTextureFor(u, v) {
    const gl = this.gl;
    const d = this.glc.defaults;
    if (u.type === gl.SAMPLER_CUBE) return d.cube;
    if (u.type === gl.SAMPLER_3D) return d.tex3d;
    if (u.type === gl.SAMPLER_2D_SHADOW) return d.shadow;
    const name = v && v.default;
    return d[name] || (name === '' || name === undefined ? d.gray : d.gray);
  }

  reportError(e) {
    const key = e.message;
    if (this.errors.some((x) => x.message === key)) return;
    this.errors.push(e);
    console.error(e.message);
    if (this.onError) this.onError(e);
  }

  // ---------------- 全屏 Blit ----------------
  // 把 source 画到 target（'screen' 或 RT），用 material 的 pass；source 绑定为 _BlitTexture 和 _MainTex
  blit(source, target, mat = null, pass = 0, uniforms = {}) {
    const gl = this.gl;
    mat = mat || this.blitMat;
    const p = typeof pass === 'number' ? mat.shader.passes[pass] : mat.shader.findPass(pass);
    if (!p) { this.reportError(new Error(`${mat.shader.name} 没有 Pass ${pass}`)); return; }
    this.bindTarget(target);
    let prog;
    try { prog = mat.shader.program(p, mat.keywords); } catch (e) { this.reportError(e); return; }
    gl.useProgram(prog.program);
    this.applyState({ cull: 'Off', zwrite: 'Off', ztest: 'Always', ...p.state }, mat);
    const src = source && (source.texture || source);
    const over = { _BlitScaleBias: [1, 1, 0, 0], _BlitMipLevel: 0, ...uniforms };
    if (src) {
      over._BlitTexture = src; over._MainTex = src; over._SourceTex = src;
      over._BlitTexture_TexelSize = [1 / src.width, 1 / src.height, src.width, src.height];
      over._MainTex_TexelSize = over._BlitTexture_TexelSize;
    }
    this.setUniforms(prog, mat, null, over);
    gl.bindVertexArray(this.fullscreenVAO);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
  }

  // ---------------- 一帧 ----------------
  render(scene, time, dt = 1 / 60) {
    const gl = this.gl;
    const W = this.canvas.width, H = this.canvas.height;
    const cam = scene.camera;
    cam.aspect = W / H;
    scene.update(time, dt);
    const frame = new Frame(this, scene, W, H, time, dt);
    this.frame = frame;
    frame.setupCamera();
    frame.setupLights();
    frame.setupEnvironment();

    // 收集 Renderer Feature 的 Pass
    const passes = [
      { event: RenderPassEvent.BeforeRenderingShadows + 1, builtin: true, run: () => frame.renderShadows() },
      { event: RenderPassEvent.BeforeRenderingOpaques + 1, builtin: true, run: () => frame.renderOpaques() },
      { event: RenderPassEvent.AfterRenderingOpaques, builtin: true, run: () => frame.copyDepth() },
      { event: RenderPassEvent.BeforeRenderingSkybox + 1, builtin: true, run: () => frame.renderSkybox() },
      { event: RenderPassEvent.AfterRenderingSkybox, builtin: true, run: () => frame.copyColor() },
      { event: RenderPassEvent.BeforeRenderingTransparents + 1, builtin: true, run: () => frame.renderTransparents() },
      { event: RenderPassEvent.BeforeRenderingPostProcessing + 1, builtin: true, run: () => frame.postProcess() },
    ];
    for (const f of scene.features) {
      if (!f.active || !f.impl) continue;
      try { f.impl.addPasses(frame, (event, run, name) => passes.push({ event, run, name: name || f.name })); } catch (e) { this.reportError(e); }
    }
    passes.forEach((p, i) => (p.order = i));
    passes.sort((a, b) => a.event - b.event || (a.builtin === b.builtin ? a.order - b.order : a.builtin ? -1 : 1));

    frame.beginCamera();
    for (const p of passes) {
      try { p.run(frame); } catch (e) { this.reportError(e); }
    }
    // 相机栈：依次画 Overlay 相机（只画它自己 Culling Mask 里的物体，叠在 Base 相机的颜色上）
    for (const ov of scene.overlayCameras || []) {
      if (!(scene.overlayRefs || []).includes(ov.index) || !ov.obj.active) continue;
      try { frame.renderOverlay(ov); } catch (e) { this.reportError(e); }
    }
    frame.finalBlit();
    gl.bindVertexArray(null);
  }
}

// ---------------- 场景 ----------------
class Scene {
  constructor(engine, doc, panel, panelIndex) {
    this.engine = engine;
    this.doc = doc;
    this.panel = panel;
    this.panelIndex = panelIndex;
    this.materials = new Map();
    this.objects = [];
    this.renderers = [];
    this.lights = [];
    this.volumes = [];
    this.features = [];
    this.behaviours = [];
    this.missingShaders = new Set();
  }

  async load(onProgress) {
    const E = this.engine, P = this.panel;
    // 1) 着色器（缺 GLSL 版本的记下来，用洋红色代替，和 Unity 一样）
    const shaderNames = new Set(Object.values(P.materials).map((m) => m.shader));
    await Promise.all([...shaderNames].map(async (n) => {
      try { await E.shaders.get(n); } catch (e) { this.missingShaders.add(n); console.warn(e.message); }
    }));
    const err = await E.shaders.get('Cookbook/Common');
    for (const [id, mj] of Object.entries(P.materials)) {
      const sh = E.shaders.getLoaded(mj.shader);
      const m = sh ? new Material(sh, mj) : new Material(err, { name: mj.name, props: {} });
      if (!sh) m.missing = mj.shader;
      m.id = id;
      m.json = mj;
      this.materials.set(id, m);
    }
    // 2) 贴图
    const texKeys = new Set();
    for (const m of Object.values(P.materials)) for (const v of Object.values(m.props)) if (v && v.texture) texKeys.add(v.texture);
    if (P.env.customReflection) texKeys.add(P.env.customReflection);
    let done = 0;
    const texMap = new Map();
    await Promise.all([...texKeys].map(async (k) => {
      try { texMap.set(k, await E.assets.texture(k)); } catch (e) { console.warn(e.message); }
      onProgress && onProgress(++done / texKeys.size);
    }));
    this.textures = texMap;
    for (const m of this.materials.values()) for (const [k, v] of m.props) if (v && v.texture) m.props.set(k, { ...v, glTexture: texMap.get(v.texture) });
    // 3) 物体
    const objs = P.objects;
    const meshKeys = new Set();
    objs.forEach((o) => o.components.forEach((c) => c.mesh && meshKeys.add(c.mesh)));
    const meshes = new Map();
    await Promise.all([...meshKeys].map(async (k) => meshes.set(k, await E.assets.mesh(k))));
    objs.forEach((o, i) => {
      const obj = {
        index: i, name: o.name, active: o.active, layer: o.layer, json: o,
        matrix: mat4.from(o.localToWorld), position: o.position.slice(),
      };
      obj.invMatrix = mat4.invert(obj.matrix);
      obj.flip = det3(obj.matrix) < 0;
      this.objects.push(obj);
      const mf = o.components.find((c) => c.mesh && !c.materials);
      for (const c of o.components) {
        if (c.type === 'UnityEngine.MeshRenderer' && mf) {
          obj.mesh = meshes.get(mf.mesh);
          obj.renderer = {
            enabled: c.enabled, materials: c.materials.map((id) => this.materials.get(id)),
            castShadows: c.castShadows !== 'Off', shadowsOnly: c.castShadows === 'ShadowsOnly',
            receiveShadows: c.receiveShadows, bounds: c.bounds, sortingOrder: c.sortingOrder,
          };
          if (obj.mesh) this.renderers.push(obj);
        } else if (c.type === 'UnityEngine.Light') {
          this.lights.push({ obj, ...c, data: o.components.find((x) => x.type.endsWith('UniversalAdditionalLightData'))?.data });
        } else if (c.type === 'UnityEngine.Camera' && i === P.mainCamera) {
          const add = o.components.find((x) => x.type.endsWith('UniversalAdditionalCameraData'));
          this.camera = new Camera(c, o, add ? add.data : {});
          // 相机栈：Base 相机的 Stack 里挂的 Overlay 相机（m_Cameras 里的 component 是物体序号）
          this.overlayRefs = ((add && add.data.m_Cameras) || []).map((r) => r && r.component).filter((x) => x !== undefined && x !== null);
        } else if (c.type === 'UnityEngine.Camera') {
          const add = o.components.find((x) => x.type.endsWith('UniversalAdditionalCameraData'));
          if (add && add.data.m_CameraType === 1 && c.enabled !== false) (this.overlayCameras = this.overlayCameras || []).push({ index: i, obj, cam: new Camera(c, o, add.data), clearDepth: !!add.data.m_ClearDepth });
          // 渲染到 RenderTexture 的副相机：交给 behaviours/UnityEngine.Camera.js，每帧先把它画进 RT（材质里引用这张 RT 的地方就有内容了）
          else if (c.targetTexture) this.behaviours.push({ obj, type: c.type, json: c });
        } else if (c.type === 'UnityEngine.Rendering.Volume') {
          this.volumes.push({ obj, ...c });
        } else if (c.type !== 'UnityEngine.MeshFilter' && c.type !== 'UnityEngine.MeshRenderer' && c.type !== 'UnityEngine.Camera' && !c.type.endsWith('AdditionalCameraData') && !c.type.endsWith('AdditionalLightData')) {
          this.behaviours.push({ obj, type: c.type, json: c });
        }
      }
    });
    this.sun = P.sun >= 0 ? this.lights.find((l) => l.obj.index === P.sun) : null;
    // 4) 环境
    this.env = P.env;
    this.skybox = P.env.skybox ? this.materials.get(P.env.skybox) : null;
    this.reflection = P.env.customReflection ? texMap.get(P.env.customReflection) : null;
    if (!this.reflection && this.skybox) { const t = this.skybox.props.get('_Tex'); this.reflection = t && t.glTexture; }
    this.asset = P.asset;
    this.rendererData = P.renderer;
    // 5) Renderer Feature 与脚本
    for (const f of P.features) {
      const entry = { ...f, impl: null };
      try { entry.impl = await loadFeature(E, f, this); } catch (e) { entry.error = e; console.warn(e.message); }
      this.features.push(entry);
    }
    for (const b of this.behaviours) {
      try { b.impl = await loadBehaviour(E, b, this); } catch (e) { b.error = e; console.warn(e.message); }
    }
    this.bounds = sceneBounds(this.renderers);
  }

  materialById(id) { return this.materials.get(id); }
  find(name) { return this.objects.find((o) => o.name === name); }

  update(time, dt) {
    for (const b of this.behaviours) if (b.impl && b.impl.update) { try { b.impl.update(time, dt); } catch (e) { this.engine.reportError(e); } }
  }

  setMatrix(obj, m) { obj.matrix = m; obj.invMatrix = mat4.invert(m); obj.flip = det3(m) < 0; }
}

function det3(m) {
  return m[0] * (m[5] * m[10] - m[6] * m[9]) - m[4] * (m[1] * m[10] - m[2] * m[9]) + m[8] * (m[1] * m[6] - m[2] * m[5]);
}

function sceneBounds(renderers) {
  let mn = [1e9, 1e9, 1e9], mx = [-1e9, -1e9, -1e9];
  for (const r of renderers) {
    const [c, e] = r.renderer.bounds;
    if (e[0] > 20 || e[2] > 20) continue;   // 大地面不算
    for (let k = 0; k < 3; k++) { mn[k] = Math.min(mn[k], c[k] - e[k]); mx[k] = Math.max(mx[k], c[k] + e[k]); }
  }
  if (mn[0] > mx[0]) return { min: [-2, -2, -2], max: [2, 2, 2] };
  return { min: mn, max: mx };
}

// ---------------- 相机（支持轨道控制） ----------------
export class Camera {
  constructor(c, o, add) {
    this.json = c;
    this.fov = c.fov; this.orthographic = c.orthographic; this.orthoSize = c.orthoSize;
    this.near = c.near; this.far = c.far; this.aspect = c.aspect;
    this.clearFlags = c.clearFlags; this.background = c.background;
    this.cullingMask = c.cullingMask;
    this.position = o.position.slice();
    this.pivot = c.pivot.slice();
    this.exportedView = mat4.from(c.worldToCamera);
    this.view = this.exportedView;
    this.postProcessing = !!add.m_RenderPostProcessing;
    this.antialiasing = add.m_Antialiasing || 0;
    this.renderShadows = add.m_RenderShadows !== false;
    this.allowHDR = c.allowHDR; this.allowMSAA = c.allowMSAA;
    // 轨道参数：从初始位置反推
    const d = vec3.sub(this.position, this.pivot);
    this.dist = vec3.len(d);
    this.yaw = Math.atan2(d[0], -d[2]);
    this.pitch = Math.asin(Math.max(-1, Math.min(1, d[1] / this.dist)));
    this.home = { yaw: this.yaw, pitch: this.pitch, dist: this.dist, pivot: this.pivot.slice(), orthoSize: this.orthoSize };
    this.moved = false;
  }

  orbit(dyaw, dpitch) { this.yaw += dyaw; this.pitch = Math.max(-1.5, Math.min(1.5, this.pitch + dpitch)); this.moved = true; this.updateView(); }
  zoom(f) { if (this.orthographic) this.orthoSize *= f; else this.dist = Math.max(0.2, this.dist * f); this.moved = true; this.updateView(); }
  pan(dx, dy) {
    const inv = mat4.invert(this.view);
    const right = mat4.transformDir(inv, [1, 0, 0]), up = mat4.transformDir(inv, [0, 1, 0]);
    const s = this.orthographic ? this.orthoSize : this.dist * Math.tan((this.fov * Math.PI) / 360);
    this.pivot = vec3.add(this.pivot, vec3.add(vec3.scale(right, -dx * s * 2), vec3.scale(up, dy * s * 2)));
    this.moved = true; this.updateView();
  }
  reset() { Object.assign(this, { ...this.home, pivot: this.home.pivot.slice() }); this.moved = false; this.view = this.exportedView; this.position = mat4.transformPoint(mat4.invert(this.view), [0, 0, 0]); }
  updateView() {
    const cp = Math.cos(this.pitch);
    this.position = vec3.add(this.pivot, [Math.sin(this.yaw) * cp * this.dist, Math.sin(this.pitch) * this.dist, -Math.cos(this.yaw) * cp * this.dist]);
    this.view = mat4.lookAtUnity(this.position, this.pivot);
  }
  projection() {
    if (this.orthographic) { const h = this.orthoSize, w = h * this.aspect; return mat4.ortho(-w, w, -h, h, this.near, this.far); }
    return mat4.perspective(this.fov, this.aspect, this.near, this.far);
  }
}

// ---------------- 一帧的上下文（Renderer Feature 也通过它干活） ----------------
export class Frame {
  constructor(engine, scene, W, H, time, dt) {
    this.engine = engine; this.gl = engine.gl; this.scene = scene; this.camera = scene.camera;
    this.width = W; this.height = H; this.time = time; this.dt = dt;
    const a = scene.asset;
    this.hdr = (scene.doc.hdr || false) && a.m_SupportsHDR !== false && this.camera.allowHDR;
    this.msaa = this.camera.allowMSAA ? (a.m_MSAA || 1) : 1;
    this.requireDepth = !!a.m_RequireDepthTexture || this.camera.json && false;
    this.requireOpaque = !!a.m_RequireOpaqueTexture;
    this.colorFormat = this.hdr ? 'RGBA16F' : 'SRGB8_ALPHA8';
  }

  // URP Asset / Renderer 上的设置（Feature 脚本读取用）
  get asset() { return this.scene.asset; }

  // 混合后的 Volume 参数：getVolume('Cookbook.Ch26.MyBloom') → {参数: 值}，没有任何 Volume 提供时返回 null
  getVolume(type) {
    if (!this._vol) this._vol = this.engine.post.resolveVolumes(this.scene);
    return this._vol[type] || null;
  }

  setupCamera() {
    const E = this.engine, cam = this.camera;
    this.view = cam.view;
    this.proj = cam.projection();
    this.viewProj = mat4.mul(this.proj, this.view);
    this.invView = mat4.invert(this.view);
    this.invProj = mat4.invert(this.proj);
    this.invViewProj = mat4.invert(this.viewProj);
    this.cameraPos = mat4.transformPoint(this.invView, [0, 0, 0]);
    const n = cam.near, f = cam.far, W = this.width, H = this.height;
    const t = this.time;
    const G = (k, v) => E.setGlobal(k, v);
    G('unity_MatrixV', this.view); G('unity_MatrixP', this.proj); G('unity_MatrixVP', this.viewProj);
    G('unity_MatrixInvV', this.invView); G('unity_MatrixInvP', this.invProj); G('unity_MatrixInvVP', this.invViewProj);
    G('unity_PrevMatrixVP', E.prevViewProj || this.viewProj);
    G('_WorldSpaceCameraPos', this.cameraPos);
    G('_Time', [t / 20, t, t * 2, t * 3]); G('_SinTime', [Math.sin(t / 8), Math.sin(t / 4), Math.sin(t / 2), Math.sin(t)]);
    G('_CosTime', [Math.cos(t / 8), Math.cos(t / 4), Math.cos(t / 2), Math.cos(t)]);
    G('unity_DeltaTime', [this.dt, 1 / this.dt, this.dt, 1 / this.dt]);
    G('_ScreenParams', [W, H, 1 + 1 / W, 1 + 1 / H]); G('_ScaledScreenParams', [W, H, 1 + 1 / W, 1 + 1 / H]);
    G('_ProjectionParams', [1, n, f, 1 / f]);
    const zx = 1 - f / n, zy = f / n;
    G('_ZBufferParams', [zx, zy, zx / f, zy / f]);
    G('unity_OrthoParams', cam.orthographic ? [cam.orthoSize * cam.aspect, cam.orthoSize, 0, 1] : [0, 0, 0, 0]);
    G('unity_CameraProjection', this.proj);
    E.prevViewProj = this.viewProj;
  }

  setupLights() {
    const E = this.engine, S = this.scene;
    const live = S.lights.filter((l) => l.obj.active && l.enabled !== false);
    let main = S.sun && live.includes(S.sun) && S.sun.lightType === 'Directional' ? S.sun : null;
    if (!main) main = live.filter((l) => l.lightType === 'Directional').sort((a, b) => b.intensity - a.intensity)[0] || null;
    this.mainLight = main;
    const G = (k, v) => E.setGlobal(k, v);
    if (main) {
      const d = vec3.scale(main.forward, -1);
      G('_MainLightPosition', [d[0], d[1], d[2], 0]);
      G('_MainLightColor', [main.finalColor[0], main.finalColor[1], main.finalColor[2], 1]);
    } else { G('_MainLightPosition', [0, 1, 0, 0]); G('_MainLightColor', [0, 0, 0, 0]); }
    // 附加光：方向光排前面，其余按到相机的距离排序，最多 32 盏（URP 桌面 Forward+ 上限更高，书里的场景够用）
    const camPos = this.cameraPos;
    const d2 = (l) => { const p = l.obj.json.position; return (p[0] - camPos[0]) ** 2 + (p[1] - camPos[1]) ** 2 + (p[2] - camPos[2]) ** 2; };
    const extra = live.filter((l) => l !== main && ['Point', 'Spot', 'Directional'].includes(l.lightType))
      .sort((a, b) => (a.lightType === 'Directional' ? 0 : 1) - (b.lightType === 'Directional' ? 0 : 1) || d2(a) - d2(b)).slice(0, 32);
    this.additionalLights = extra;
    const N = 32 * 4;
    const pos = new Float32Array(N), col = new Float32Array(N), att = new Float32Array(N), dir = new Float32Array(N);
    extra.forEach((l, i) => {
      const p = l.obj.json.position;
      if (l.lightType === 'Directional') { pos.set([-l.forward[0], -l.forward[1], -l.forward[2], 0], i * 4); }
      else pos.set([p[0], p[1], p[2], 1], i * 4);
      col.set([l.finalColor[0], l.finalColor[1], l.finalColor[2], 1], i * 4);
      let z = 0, w = 1;
      if (l.lightType === 'Spot') {
        const cosOuter = Math.cos((l.spotAngle * Math.PI) / 360);
        const cosInner = Math.cos(((l.innerSpotAngle || l.spotAngle * 0.8) * Math.PI) / 360);
        const inv = 1 / Math.max(0.001, cosInner - cosOuter);
        z = inv; w = -cosOuter * inv;
      }
      const r2 = l.lightType === 'Directional' ? 0 : 1 / Math.max(0.0001, l.range * l.range);
      att.set([r2, 0, z, w], i * 4);
      dir.set([-l.forward[0], -l.forward[1], -l.forward[2], 0], i * 4);
    });
    // Forward 路径：逐物体挑最重要的几盏灯（Per Object Limit），和 URP 一样
    const mode = this.scene.rendererData.m_RenderingMode ?? 0;   // 0 Forward，1 Deferred，2 Forward+
    const perObject = mode === 0;
    G('_PerObjectLights', perObject ? 1 : 0);
    if (perObject) {
      const limit = Math.min(8, this.scene.asset.m_AdditionalLightsPerObjectLimit ?? 4);
      for (const o of this.scene.renderers) {
        const [c, e] = o.renderer.bounds;
        const cand = [];
        extra.forEach((l, i) => {
          if (l.lightType === 'Directional') { cand.push({ i, score: 1e9 }); return; }
          const p = l.obj.json.position;
          // 灯的范围球与物体包围盒相交才算
          let dd = 0;
          for (let k = 0; k < 3; k++) { const v = Math.max(Math.abs(p[k] - c[k]) - e[k], 0); dd += v * v; }
          if (dd > l.range * l.range) return;
          // 重要度：灯的亮度 / 到物体中心距离的平方（大地面这种物体，离中心近的灯优先）
          const lum = 0.2126 * l.finalColor[0] + 0.7152 * l.finalColor[1] + 0.0722 * l.finalColor[2];
          const dc = (p[0] - c[0]) ** 2 + (p[1] - c[1]) ** 2 + (p[2] - c[2]) ** 2;
          cand.push({ i, score: lum / Math.max(dc, 0.01) });
        });
        cand.sort((a, b) => b.score - a.score);
        const idx = cand.slice(0, limit).map((x) => x.i);
        o.uniforms = o.uniforms || {};
        o.uniforms.unity_LightData = [0, idx.length, 0, 0];
        const li = new Float32Array(8);
        idx.forEach((v, k) => (li[k] = v));
        o.uniforms.unity_LightIndices = li;
      }
    }
    G('_AdditionalLightsCount', [extra.length, 0, 0, 0]);
    G('_AdditionalLightsPosition', pos); G('_AdditionalLightsColor', col);
    G('_AdditionalLightsAttenuation', att); G('_AdditionalLightsSpotDir', dir);
    // Light Layers：灯的 Rendering Layers 与物体的 Rendering Layer Mask 按位与，不相交就不照（URP Asset 打开时生效）
    G('_LightLayers', this.scene.asset.m_SupportsLightLayers ? 1 : 0);
    const layerOf = (l) => (l && l.data ? l.data.m_RenderingLayers ?? l.data.m_LightLayerMask ?? 1 : 1);
    G('_MainLightLayerMask', layerOf(main));
    const lm = new Float32Array(32);
    extra.forEach((l, i) => (lm[i] = layerOf(l)));
    G('_AdditionalLightsLayerMasks', lm);
    for (const o of this.scene.renderers) {
      const r = o.json.components.find((c) => c.renderingLayerMask !== undefined);
      o.uniforms = o.uniforms || {};
      o.uniforms.unity_RenderingLayer = [r ? r.renderingLayerMask : 1, 0, 0, 0];
    }
  }

  setupEnvironment() {
    const E = this.engine, env = this.scene.env;
    const sh = env.ambientProbe, G = (k, v) => E.setGlobal(k, v);
    const c = (ch, i) => sh[ch * 9 + i];
    const A = (ch) => [c(ch, 3), c(ch, 1), c(ch, 2), c(ch, 0) - c(ch, 6)];
    const B = (ch) => [c(ch, 4), c(ch, 5), c(ch, 6) * 3, c(ch, 7)];
    G('unity_SHAr', A(0)); G('unity_SHAg', A(1)); G('unity_SHAb', A(2));
    G('unity_SHBr', B(0)); G('unity_SHBg', B(1)); G('unity_SHBb', B(2));
    G('unity_SHC', [c(0, 8), c(1, 8), c(2, 8), 1]);
    G('unity_SpecCube0', this.scene.reflection || E.glc.defaults.cube);
    G('unity_SpecCube0_HDR', [env.reflectionIntensity, 1, 0, 0]);
    G('_GlossyEnvironmentColor', [c(0, 0) * env.reflectionIntensity, c(1, 0) * env.reflectionIntensity, c(2, 0) * env.reflectionIntensity, 1]);
    // 雾
    if (env.fog) {
      const mode = { Linear: 1, Exponential: 2, ExponentialSquared: 3 }[env.fogMode] || 0;
      const d = env.fogDensity, s = env.fogStart, e = env.fogEnd;
      G('unity_FogParams', [d / Math.sqrt(Math.LN2), d / Math.LN2, -1 / (e - s), e / (e - s)]);
      G('unity_FogColor', env.fogColor); G('unity_FogMode', [mode, 0, 0, 0]);
    } else G('unity_FogMode', [0, 0, 0, 0]);
    G('_AmbientOcclusionParam', [0, 0, 0, 0]);
  }

  // ---------------- 相机目标 ----------------
  beginCamera() {
    const E = this.engine, gl = this.gl, cam = this.camera;
    this.cameraTarget = E.rt('camera', this.width, this.height, { color: this.colorFormat, depth: 'DEPTH24_STENCIL8', samples: this.msaa, renderbuffers: true });
    E.bindTarget(this.cameraTarget);
    gl.depthMask(true); gl.colorMask(true, true, true, true); gl.stencilMask(255);
    const bg = cam.clearFlags === 'SolidColor' ? cam.background : [0, 0, 0, 0];
    gl.clearColor(bg[0], bg[1], bg[2], bg[3]);
    gl.clearDepth(1); gl.clearStencil(0);
    gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT | gl.STENCIL_BUFFER_BIT);
    // 和 URP 一样（Copy Depth = After Opaques）：不透明物体在拷贝之前读 _CameraDepthTexture，拿到的是上一帧拷贝的深度
    const prev = this.requireDepth && this.cameraTarget.depthCopyOf === this.camera ? this.cameraTarget.depthTexture : null;
    E.setGlobal('_CameraDepthTexture', prev || E.glc.defaults.white);
    // 没开 Opaque Texture 时的占位：和 Unity 的 Texture2D.grayTexture 一样是 sRGB 的 0.5 灰（线性约 0.21）
    if (!E.glc.defaults.graySRGB) E.glc.defaults.graySRGB = E.glc.texture2D(1, 1, 'SRGB8_ALPHA8', new Uint8Array([128, 128, 128, 255]), { mips: false, filter: 'Point' });
    E.setGlobal('_CameraOpaqueTexture', E.glc.defaults.graySRGB);
  }

  // 当前相机颜色的内容（会先 resolve）
  cameraColorTexture() { this.engine.glc.resolve(this.cameraTarget, { color: true }); return this.cameraTarget.texture; }
  cameraDepthTexture() { this.engine.glc.resolve(this.cameraTarget, { color: false, depth: true }); return this.cameraTarget.depthTexture; }
  bindCamera() { this.engine.bindTarget(this.cameraTarget); }
  getTemporaryRT(name, w, h, opts = {}) { return this.engine.rt('tmp:' + name, w, h, { color: opts.color || this.colorFormat, depth: opts.depth || null, samples: 1, filter: opts.filter || 'Bilinear', mips: opts.mips || false }); }
  blit(src, dst, mat, pass, uniforms) { this.engine.blit(src, dst === 'camera' ? this.cameraTarget : dst, mat, pass, uniforms); }
  setGlobal(k, v) { this.engine.setGlobal(k, v); }

  // ---------------- 可见物体 ----------------
  visibleRenderers(layerMask = -1) {
    return this.scene.renderers.filter((o) => o.active && o.renderer.enabled && (this.camera.cullingMask & (1 << o.layer)) !== 0 && (layerMask & (1 << o.layer)) !== 0);
  }

  // 通用的 DrawRenderers：queue 'opaque' | 'transparent' | 'all' | [min,max]；lightModes 为 Pass 的 LightMode 列表
  // overrideShader：换着色器但保留各物体原材质的属性与关键字（RenderObjects 的 Override Mode = Shader）
  drawRenderers({ queue = 'opaque', lightModes = OPAQUE_PASSES, layerMask = -1, overrideMaterial = null, overrideShader = null, overridePass = 0, state = null, sort = null, overrides = null, filter = null, matFilter = null } = {}) {
    const E = this.engine;
    const [qmin, qmax] = Array.isArray(queue) ? queue : queue === 'opaque' ? [0, 2500] : queue === 'transparent' ? [2501, 5000] : [0, 5000];
    const items = [];
    const camPos = this.cameraPos;
    for (const o of this.visibleRenderers(layerMask)) {
      if (filter && !filter(o)) continue;
      if (o.renderer.shadowsOnly) continue;
      o.renderer.materials.forEach((m, si) => {
        if (!m || (matFilter && !matFilter(m))) return;
        const q = m.renderQueue;
        if (q < qmin || q > qmax) return;
        const c = o.renderer.bounds[0];
        const d = (c[0] - camPos[0]) ** 2 + (c[1] - camPos[1]) ** 2 + (c[2] - camPos[2]) ** 2;
        items.push({ o, si, m, q, d });
      });
    }
    const back = sort === 'backToFront' || (sort === null && qmin > 2500);
    items.sort((a, b) => a.q - b.q || (back ? b.d - a.d : a.d - b.d));
    for (const it of items) {
      if (overrideMaterial || overrideShader) {
        // 和 URP 一样：只给 Shader 里有 lightModes 里的 Pass 的物体画覆盖材质
        if (!it.m.shader.passes.some((p) => lightModes.includes(p.lightMode))) continue;
        const om = overrideMaterial || shaderOverrideMaterial(it.m, overrideShader);
        const pass = typeof overridePass === 'number' ? om.shader.passes[overridePass] : om.shader.findPass(overridePass);
        if (pass) E.draw(it.o, it.si, om, pass, { state: state ? { ...pass.state, ...state } : null, overrides });   // 覆盖的只是深度/模板，混合、剔除等仍用覆盖材质 Pass 自己的
        continue;
      }
      for (const lm of lightModes) {
        for (const pass of it.m.shader.passes) {
          if (pass.lightMode !== lm || it.m.disabledPasses.has(lm)) continue;
          E.draw(it.o, it.si, it.m, pass, { state: state ? { ...pass.state, ...state } : null, overrides });
        }
      }
    }
  }

  // Universal Renderer 的 Opaque/Transparent Layer Mask（RenderObjects 常配合它把某些层交给 Feature 画）
  renderOpaques() {
    this.bindCamera();
    const lm = layerMask(this.scene.rendererData.m_OpaqueLayerMask);
    if ((this.scene.rendererData.m_RenderingMode ?? 0) !== 1) { this.drawRenderers({ queue: 'opaque', layerMask: lm }); return; }
    // Deferred：网页版没有 GBuffer，有 UniversalGBuffer Pass 的材质仍用前向 Pass 近似“GBuffer + 延迟光照”；
    // 没有 GBuffer Pass 的材质只会被 URP 的 Forward Only 绘制画到（UniversalForwardOnly / SRPDefaultUnlit），只有 UniversalForward 的会消失
    const hasGBuffer = (m) => !!m.missing || !(m.shader.meta.passes || []).length || m.shader.meta.passes.some((p) => p.lightMode === 'UniversalGBuffer');
    this.drawRenderers({ queue: 'opaque', layerMask: lm, matFilter: hasGBuffer });
    this.drawRenderers({ queue: 'opaque', layerMask: lm, matFilter: (m) => !hasGBuffer(m), lightModes: ['UniversalForwardOnly', 'SRPDefaultUnlit', 'LightweightForward'] });
  }
  renderTransparents() { this.bindCamera(); this.drawRenderers({ queue: 'transparent', layerMask: layerMask(this.scene.rendererData.m_TransparentLayerMask) }); }

  copyDepth() {
    if (!this.requireDepth) return;
    this.engine.setGlobal('_CameraDepthTexture', this.cameraDepthTexture());
    this.cameraTarget.depthCopyOf = this.camera;
  }

  copyColor() {
    if (!this.requireOpaque) return;
    const E = this.engine;
    const src = this.cameraColorTexture();
    const ds = this.scene.asset.m_OpaqueDownsampling ?? 1;
    const div = ds === 0 ? 1 : ds === 1 ? 2 : 4;
    const rt = E.rt('opaque', Math.max(1, this.width / div | 0), Math.max(1, this.height / div | 0), { color: this.colorFormat, samples: 1 });
    E.blit(src, rt, E.blitMat, 0);
    E.setGlobal('_CameraOpaqueTexture', rt.texture);
    this.bindCamera();
  }

  renderSkybox() {
    const sky = this.scene.skybox;
    if (!sky || this.camera.clearFlags !== 'Skybox') return;
    const E = this.engine;
    this.bindCamera();
    const pass = sky.shader.passes[0];
    const obj = { mesh: E.skyCube, matrix: mat4.identity(), invMatrix: mat4.identity(), flip: false };
    E.draw(obj, 0, sky, pass);
  }

  // ---------------- 阴影 ----------------
  // 和 Unity 一样，投影物也受相机 Culling Mask 过滤（不在本相机层里的物体不投影）
  casters() { return this.scene.renderers.filter((o) => o.active && o.renderer.enabled && o.renderer.castShadows && (this.camera.cullingMask & (1 << o.layer)) !== 0); }

  // 相机栈里的 Overlay 相机：换成它的矩阵，重画阴影（只含它自己层里的投影物），按需清深度，再画不透明和半透明物体。
  // Overlay 相机不清颜色、不画天空盒；后处理只在 Base 相机上做（URP 14 里栈的后处理在最后一个相机，这里简化）
  renderOverlay(ov) {
    const gl = this.gl, base = this.camera, prevVP = this.engine.prevViewProj;
    this.camera = ov.cam;
    ov.cam.aspect = this.width / this.height;
    try {
      this.setupCamera();
      if (ov.cam.renderShadows) this.renderShadows();
      this.bindCamera();
      if (ov.clearDepth) { gl.depthMask(true); gl.stencilMask(255); gl.clearDepth(1); gl.clearStencil(0); gl.clear(gl.DEPTH_BUFFER_BIT | gl.STENCIL_BUFFER_BIT); }
      this.renderOpaques();
      this.renderTransparents();
    } finally { this.camera = base; this.engine.prevViewProj = prevVP; }
  }

  renderShadows() {
    const E = this.engine, gl = this.gl, a = this.scene.asset;
    E.setGlobal('_MainLightShadowParams', [0, 0, 0, 1]);
    E.setGlobal('_MainLightShadowmapTexture', E.glc.defaults.shadow);
    E.setGlobal('_AdditionalLightsShadowmapTexture', E.glc.defaults.shadow);
    E.setGlobal('_AdditionalShadowParams', new Float32Array(32).fill(-1));
    E.setGlobal('_AdditionalLightsWorldToShadow', new Float32Array(16 * 8));
    E.setGlobal('_MainLightShadowsCascade', 0);
    E.setGlobal('_MainLightShadowsScreen', 0);
    const L = this.mainLight;
    const soft = a.m_SoftShadowsSupported !== false;
    if (L && L.shadows !== 'None' && a.m_MainLightShadowsSupported !== false && this.camera.renderShadows) {
      // 级联阴影（URP MainLightShadowCasterPass）：1 级用整张图；2 级图集为 res×res/2；3~4 级为 res×res，每级占 res/2 的一格
      const res = Math.min(4096, a.m_MainLightShadowmapResolution || 2048);
      const maxD = Math.min(a.m_ShadowDistance || 50, this.camera.far);
      const spheres = this.cascadeSpheres(maxD);
      const nc = spheres.length;
      const atlasW = res, atlasH = nc === 2 ? res / 2 : res, tile = nc === 1 ? res : res / 2;
      const rt = E.rt('mainShadow', atlasW, atlasH, { color: null, depth: 'DEPTH24' });
      E.glc.setShadowCompare(rt.depthTexture.tex);
      E.bindTarget(rt);
      gl.depthMask(true); gl.clearDepth(1); gl.clear(gl.DEPTH_BUFFER_BIT);
      // 软阴影：滤波档位取 Asset 的 Soft Shadow Quality（1 Low / 2 Medium / 3 High）；偏移按滤波核半径放大（ShadowUtils.GetShadowBias）
      const isSoft = soft && L.shadows === 'Soft';
      const quality = isSoft ? Math.max(1, a.m_SoftShadowQuality ?? 2) : 0;
      const lq = (L.data && L.data.m_SoftShadowQuality) || 0;   // 灯上的设置，0 = Use Pipeline Settings
      const k = isSoft ? (lq === 1 ? 1.5 : lq === 3 ? 3.5 : 2.5) : 1;
      const dir = vec3.scale(L.forward, -1);
      const mats = new Float32Array(16 * 5);   // 第 5 个是“超出所有级联”用的空矩阵（z = 0 → 视为无阴影）
      spheres.forEach((sp, ci) => {
        const { view, proj } = this.fitDirectionalShadow(L, sp, tile);
        const vp = mat4.mul(proj, view);
        const texel = (2 / proj[0]) / tile;
        const depthBias = -(a.m_ShadowDepthBias ?? 1) * texel * k, normalBias = -(a.m_ShadowNormalBias ?? 1) * texel * k;
        const tx = (ci % 2) * tile, ty = ((ci / 2) | 0) * tile;
        gl.viewport(tx, ty, tile, tile);
        this.renderShadowCasters(null, vp, view, proj, { _ShadowBias: [depthBias, normalBias, 0, 0], _LightDirection: dir, _CastingPunctualLightShadow: 0 });
        // NDC → 图集里这一格的 UV
        const sx = 0.5 * tile / atlasW, sy = 0.5 * tile / atlasH;
        const bias = new Float32Array([sx, 0, 0, 0, 0, sy, 0, 0, 0, 0, 0.5, 0, sx + tx / atlasW, sy + ty / atlasH, 0.5, 1]);
        mats.set(mat4.mul(bias, vp), ci * 16);
      });
      E.setGlobal('_MainLightWorldToShadow', mats);
      E.setGlobal('_MainLightShadowmapTexture', rt.depthTexture);
      E.setGlobal('_MainLightShadowmapSize', [1 / atlasW, 1 / atlasH, atlasW, atlasH]);
      // 淡出：与 URP 的 GetScaleAndBiasForLinearDistanceFade 相同（border = Cascade Border）
      const sq = maxD * maxD;
      const bd = 1 - (a.m_CascadeBorder ?? 0.2), near = bd * bd * sq;
      const scale = 1 / (sq - near), biasF = -near / (sq - near);
      E.setGlobal('_MainLightShadowParams', [L.shadowStrength, quality, scale, biasF]);
      this.setupCascadeSpheres(spheres);
    }
    // 附加光源（聚光灯）阴影：一张图集，每盏灯一格
    const spots = this.additionalLights.map((l, i) => ({ l, i })).filter(({ l, i }) => i < 8 && l.lightType === 'Spot' && l.shadows !== 'None');
    if (spots.length && a.m_AdditionalLightShadowsSupported !== false) {
      const res = a.m_AdditionalLightsShadowmapResolution || 2048;
      const n = Math.ceil(Math.sqrt(spots.length)), tile = res / n;
      const rt = E.rt('addShadow', res, res, { color: null, depth: 'DEPTH24' });
      E.glc.setShadowCompare(rt.depthTexture.tex);
      E.bindTarget(rt);
      gl.depthMask(true); gl.clearDepth(1); gl.clear(gl.DEPTH_BUFFER_BIT);
      const mats = new Float32Array(16 * 8), params = new Float32Array(32).fill(-1);
      spots.forEach(({ l, i }, k) => {
        const tx = k % n, ty = (k / n) | 0;
        const pos = l.obj.json.position;
        const view = mat4.lookAtUnity(pos, vec3.add(pos, l.forward), Math.abs(l.forward[1]) > 0.99 ? [1, 0, 0] : [0, 1, 0]);
        const proj = mat4.perspective(l.spotAngle, 1, 0.05, l.range);
        const vp = mat4.mul(proj, view);
        const texel = (2 * Math.tan((l.spotAngle * Math.PI) / 360)) / tile;
        const k2 = soft && l.shadows === 'Soft' ? 2.5 : 1;
        gl.viewport(tx * tile, ty * tile, tile, tile);
        this.renderShadowCasters(null, vp, view, proj, { _ShadowBias: [-(a.m_ShadowDepthBias ?? 1) * texel * k2 * 0.5, -(a.m_ShadowNormalBias ?? 1) * texel * k2 * 0.5, 0, 0], _LightPosition: pos, _CastingPunctualLightShadow: 1, _LightDirection: vec3.scale(l.forward, -1) });
        const s = 0.5 / n;
        const bias = new Float32Array([s, 0, 0, 0, 0, s, 0, 0, 0, 0, 0.5, 0, s + tx / n, s + ty / n, 0.5, 1]);
        mats.set(mat4.mul(bias, vp), i * 16);
        params.set([l.shadowStrength, soft && l.shadows === 'Soft' ? Math.max(1, a.m_SoftShadowQuality ?? 2) : 0, 0, k], i * 4);
      });
      E.setGlobal('_AdditionalLightsWorldToShadow', mats);
      E.setGlobal('_AdditionalShadowParams', params);
      E.setGlobal('_AdditionalLightsShadowmapTexture', rt.depthTexture);
      E.setGlobal('_AdditionalShadowmapSize', [1 / res, 1 / res, res, res]);
    }
  }

  // 级联包围球（URP 的 _CascadeShadowSplitSpheres0~3）：每级取相机视锥在 [上一级分割距离, 本级分割距离] 之间
  // 那一段的最小外接球（对应 URP Asset 的 Conservative Enclosing Sphere）。阴影图每级就是这个球在光源空间的外接正方形。
  cascadeSpheres(shadowDistance) {
    const a = this.scene.asset, cam = this.camera, n = Math.max(1, Math.min(4, a.m_ShadowCascadeCount || 1));
    const split = n === 2 ? [a.m_Cascade2Split ?? 0.25] : n === 3 ? (a.m_Cascade3Split || [0.1, 0.3]) : n === 4 ? (a.m_Cascade4Split || [0.067, 0.2, 0.467]) : [];
    const ends = [...split, 1].map((x) => x * shadowDistance);
    const out = [];
    const tx = 1 / this.proj[0], ty = 1 / this.proj[5], k2 = tx * tx + ty * ty;
    for (let i = 0; i < n; i++) {
      const zn = i === 0 ? cam.near : ends[i - 1], zf = ends[i];
      let c, r2;
      if (cam.orthographic) { c = (zn + zf) / 2; r2 = ((zf - zn) / 2) ** 2 + k2; }
      else {
        c = ((zf + zn) * (1 + k2)) / 2;
        if (c >= zf) { c = zf; r2 = k2 * zf * zf; } else r2 = (zf - c) ** 2 + k2 * zf * zf;
      }
      const p = mat4.transformPoint(this.invView, [0, 0, -c]);
      out.push([p[0], p[1], p[2], Math.sqrt(r2)]);
    }
    return out;
  }

  setupCascadeSpheres(spheres) {
    const n = spheres.length;
    const sph = [[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]], radii = [0, 0, 0, 0];
    for (let i = 0; n > 1 && i < n; i++) { sph[i] = spheres[i]; radii[i] = spheres[i][3] ** 2; }
    const E = this.engine;
    E.setGlobal('_MainLightShadowsCascade', n > 1 ? 1 : 0);
    sph.forEach((v, i) => E.setGlobal('_CascadeShadowSplitSpheres' + i, v));
    E.setGlobal('_CascadeShadowSplitSphereRadii', radii);
  }

  renderShadowCasters(rt, vp, view, proj, uniforms) {
    const E = this.engine, gl = this.gl;
    if (rt) { E.bindTarget(rt); gl.depthMask(true); gl.clearDepth(1); gl.clear(gl.DEPTH_BUFFER_BIT); }
    const saved = ['unity_MatrixVP', 'unity_MatrixV', 'unity_MatrixP'].map((k) => [k, E.globals.get(k)]);
    E.setGlobal('unity_MatrixVP', vp); E.setGlobal('unity_MatrixV', view); E.setGlobal('unity_MatrixP', proj);
    for (const [k, v] of Object.entries(uniforms)) E.setGlobal(k, v);
    for (const o of this.casters()) {
      o.renderer.materials.forEach((m, si) => {
        if (!m || m.disabledPasses.has('ShadowCaster')) return;
        const pass = m.shader.passes.find((p) => p.lightMode === 'ShadowCaster');
        // URP 的 ShadowUtils.RenderShadowSlice 在画投影物前 SetGlobalDepthBias(1, 2.5)：硬件斜率偏移，等价于 Offset 2.5, 1
        if (pass) E.draw(o, si, m, pass, { state: pass.state.offset ? null : { ...pass.state, offset: [2.5, 1] } });
      });
    }
    for (const [k, v] of saved) E.setGlobal(k, v);
  }

  // 方向光阴影（一级级联）：和 Unity 一样，正交投影是级联包围球在光源空间的外接正方形，
  // 中心按 texel 对齐（相机移动时阴影边缘不闪烁）；深度范围往光源方向延伸，把球外但能投影进来的物体也包进来
  fitDirectionalShadow(L, sphere, tileRes) {
    const b = this.scene.bounds;
    const up = Math.abs(L.forward[1]) > 0.99 ? [0, 0, 1] : [0, 1, 0];
    const view = mat4.lookAtUnity([0, 0, 0], L.forward, up);
    const r = sphere[3], texel = (2 * r) / tileRes;
    const q = mat4.transformPoint(view, sphere);
    const cx = Math.floor(q[0] / texel) * texel, cy = Math.floor(q[1] / texel) * texel;
    let zmin = q[2] - r, zmax = q[2] + r;
    for (let i = 0; i < 8; i++) {
      const p = [i & 1 ? b.max[0] : b.min[0], i & 2 ? b.max[1] : b.min[1], i & 4 ? b.max[2] : b.min[2]];
      zmax = Math.max(zmax, mat4.transformPoint(view, p)[2]);
    }
    const proj = mat4.ortho(cx - r, cx + r, cy - r, cy + r, -zmax - 1, -zmin + 1);
    return { view, proj };
  }

  // ---------------- 后处理与输出 ----------------
  postProcess() {
    this.postDone = false;
    if (!this.camera.postProcessing) return;
    this.engine.post.render(this);
    this.postDone = true;
  }

  finalBlit() {
    const E = this.engine;
    const src = this.postDone ? this.postOutput : this.cameraColorTexture();
    // 画布是线性 RGBA8：在 shader 里做 线性→sRGB（HDR 的值在这里被截到 1）
    const isSrgbTex = !this.postDone && this.colorFormat === 'SRGB8_ALPHA8';
    E.blit(src, 'screen', E.blitMat, 'FinalBlit', { _SrcIsLinearEncoded: isSrgbTex ? 1 : 0, _OutputSRGB: this.postOutputIsSRGB ? 0 : 1 });
  }
}

// ---------------- 其它 ----------------
function cmpFunc(gl, n) {
  return { Never: gl.NEVER, Less: gl.LESS, Equal: gl.EQUAL, LEqual: gl.LEQUAL, LessEqual: gl.LEQUAL, Greater: gl.GREATER, NotEqual: gl.NOTEQUAL, GEqual: gl.GEQUAL, GreaterEqual: gl.GEQUAL, Always: gl.ALWAYS, Disabled: gl.ALWAYS }[n] ?? gl.LEQUAL;
}
function blendFactor(gl, v) {
  if (typeof v === 'number') v = ['Zero', 'One', 'DstColor', 'SrcColor', 'OneMinusDstColor', 'SrcAlpha', 'OneMinusSrcColor', 'DstAlpha', 'OneMinusDstAlpha', 'SrcAlphaSaturate', 'OneMinusSrcAlpha'][v];
  return { Zero: gl.ZERO, One: gl.ONE, DstColor: gl.DST_COLOR, SrcColor: gl.SRC_COLOR, OneMinusDstColor: gl.ONE_MINUS_DST_COLOR, SrcAlpha: gl.SRC_ALPHA, OneMinusSrcColor: gl.ONE_MINUS_SRC_COLOR, DstAlpha: gl.DST_ALPHA, OneMinusDstAlpha: gl.ONE_MINUS_DST_ALPHA, SrcAlphaSaturate: gl.SRC_ALPHA_SATURATE, OneMinusSrcAlpha: gl.ONE_MINUS_SRC_ALPHA }[v];
}
function blendOp(gl, v) {
  if (typeof v === 'number') v = ['Add', 'Sub', 'RevSub', 'Min', 'Max'][v];
  return { Add: gl.FUNC_ADD, Sub: gl.FUNC_SUBTRACT, RevSub: gl.FUNC_REVERSE_SUBTRACT, Min: gl.MIN, Max: gl.MAX }[v] ?? gl.FUNC_ADD;
}
function stencilOp(gl, v) {
  if (typeof v === 'number') v = ['Keep', 'Zero', 'Replace', 'IncrSat', 'DecrSat', 'Invert', 'IncrWrap', 'DecrWrap'][v];
  return { Keep: gl.KEEP, Zero: gl.ZERO, Replace: gl.REPLACE, IncrSat: gl.INCR, DecrSat: gl.DECR, Invert: gl.INVERT, IncrWrap: gl.INCR_WRAP, DecrWrap: gl.DECR_WRAP }[v] ?? gl.KEEP;
}

function cubeMesh() {
  const p = [-1, -1, -1, 1, -1, -1, 1, 1, -1, -1, 1, -1, -1, -1, 1, 1, -1, 1, 1, 1, 1, -1, 1, 1];
  const idx = [0, 1, 2, 0, 2, 3, 5, 4, 7, 5, 7, 6, 4, 0, 3, 4, 3, 7, 1, 5, 6, 1, 6, 2, 3, 2, 6, 3, 6, 7, 4, 5, 1, 4, 1, 0];
  const body = new ArrayBuffer(p.length * 4 + idx.length * 4);
  new Float32Array(body, 0, p.length).set(p);
  new Uint32Array(body, p.length * 4, idx.length).set(idx);
  return [{ vertexCount: 8, attributes: { position: { offset: 0, comps: 3 } }, indexOffset: p.length * 4, indexCount: idx.length, subMeshes: [{ start: 0, count: idx.length, topology: 'Triangles' }], bounds: [[0, 0, 0], [1, 1, 1]] }, body];
}

// Override Shader：新着色器 + 原材质的属性表与关键字（共用同一个 Map/Set，参数面板改动实时生效）
function shaderOverrideMaterial(m, shader) {
  const cache = m._shaderOverrides || (m._shaderOverrides = new Map());
  let om = cache.get(shader);
  if (!om) { om = new Material(shader); om.props = m.props; om.keywords = m.keywords; cache.set(shader, om); }
  return om;
}
