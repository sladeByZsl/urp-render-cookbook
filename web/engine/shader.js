// 着色器库与材质：按 Unity 名字找到 GLSL 文件，解析、预加载 include，按 Pass + 关键字缓存编译好的程序。
import { parseShaderLab, findIncludes, findKeywords, SourceBuilder, mapErrors, STAGE_PRELUDE, ATTRIBS } from './shaderlab.js';
import { ShaderError } from './gl.js';
import { srgbToLinear, linearToSrgb } from './math.js';

// URP 自带着色器 → 本站的 GLSL 移植
export const BUILTIN_SHADERS = {
  'Universal Render Pipeline/Lit': 'URP/Lit.glsl',
  'Universal Render Pipeline/Simple Lit': 'URP/SimpleLit.glsl',
  'Universal Render Pipeline/Unlit': 'URP/Unlit.glsl',
  'Universal Render Pipeline/Particles/Unlit': 'URP/ParticlesUnlit.glsl',
  'Universal Render Pipeline/Particles/Lit': 'URP/ParticlesLit.glsl',
  'Universal Render Pipeline/Particles/Simple Lit': 'URP/ParticlesLit.glsl',
  'Universal Render Pipeline/Baked Lit': 'URP/SimpleLit.glsl',
  'Universal Render Pipeline/Complex Lit': 'URP/ComplexLit.glsl',
  'Skybox/Cubemap': 'URP/SkyboxCubemap.glsl',
  'Skybox/Procedural': 'URP/SkyboxProcedural.glsl',
  'Cookbook/Common': 'Common.glsl',
  'Hidden/Cookbook/Blit': 'URP/Blit.glsl',
  'Hidden/Universal Render Pipeline/Blit': 'URP/Blit.glsl',
  'Hidden/Cookbook/PostFX': 'URP/PostFX.glsl',
  'Sprites/Default': 'URP/Unlit.glsl',
  'Shader Graphs/Decal': 'URP/Decal.glsl',
  'Hidden/Universal Render Pipeline/ScreenSpaceShadows': 'URP/ScreenSpaceShadows.glsl',
};

// 引擎始终提供的 URP 全局关键字（阴影、附加光源都开）
export const GLOBAL_KEYWORDS = ['_MAIN_LIGHT_SHADOWS', '_ADDITIONAL_LIGHTS', '_ADDITIONAL_LIGHT_SHADOWS', '_SHADOWS_SOFT'];

const PRECISION = `#version 300 es
precision highp float;
precision highp int;
precision highp sampler2D;
precision highp samplerCube;
precision highp sampler3D;
precision highp sampler2DShadow;
`;

export class ShaderLibrary {
  constructor(glc, assets) {
    this.glc = glc;
    this.assets = assets;
    this.meta = {};              // shaders.json：Unity 名字 → {path, props, passes, keywords}
    this.texts = new Map();      // 文件路径 → 源码（可被在线编辑覆盖）
    this.shaders = new Map();    // Unity 名字 → Shader
    this.listeners = new Set();
  }

  async init() {
    this.meta = await this.assets.json('data/shaders.json');
    this.core = await this.assets.text('engine/glsl/Core.glsl');
    this.lighting = await this.assets.text('engine/glsl/Lighting.glsl');
  }

  fileFor(name) {
    if (BUILTIN_SHADERS[name]) return BUILTIN_SHADERS[name];
    const m = this.meta[name];
    if (m && m.path && !m.path.startsWith('Packages/')) return m.path.replace(/\.[^./]+$/, '.glsl');
    return null;
  }

  async loadText(file) {
    if (this.texts.has(file)) return this.texts.get(file);
    const t = await this.assets.text('shaders/' + file);
    if (!this.texts.has(file)) this.texts.set(file, t);
    return this.texts.get(file);
  }

  // 递归预加载 include 与 UsePass 引用的着色器
  async preload(file, seen = new Set()) {
    if (seen.has(file)) return;
    seen.add(file);
    const text = await this.loadText(file);
    await Promise.all(findIncludes(text).map((inc) => this.preload(inc, seen)));
    const uses = [...text.matchAll(/UsePass\s+"([^"]+)"/g)].map((m) => m[1].slice(0, m[1].lastIndexOf('/')));
    await Promise.all(uses.map((n) => { const f = this.fileFor(n); return f ? this.preload(f, seen) : null; }));
  }

  async get(name) {
    if (this.shaders.has(name)) return this.shaders.get(name);
    const file = this.fileFor(name);
    if (!file) throw new Error(`没有 “${name}” 的 GLSL 版本`);
    await this.preload(file);
    const sh = new Shader(this, name, file);
    sh.build();
    this.shaders.set(name, sh);
    return sh;
  }

  getLoaded(name) { return this.shaders.get(name); }

  // 在线编辑：替换源码并让所有用到它的着色器重新解析；返回错误列表（空 = 成功）
  async setSource(file, text) {
    this.texts.set(file, text);
    await this.preload(file, new Set());
    const errors = [];
    for (const sh of this.shaders.values()) {
      if (!sh.dependsOn(file)) continue;
      try { sh.build(); } catch (e) { errors.push({ shader: sh.name, message: e.message }); }
    }
    this.listeners.forEach((f) => f(file));
    return errors;
  }

  include(path) {
    const text = this.texts.get(path);
    return text === undefined ? null : { text, file: path };
  }
}

export class Shader {
  constructor(lib, name, file) {
    this.lib = lib;
    this.name = name;
    this.file = file;
    this.meta = lib.meta[name] || { props: [], passes: [] };
    this.programs = new Map();
    this.version = 0;
  }

  dependsOn(file) { return this.files && this.files.has(file); }

  build() {
    const text = this.lib.texts.get(this.file);
    const ast = parseShaderLab(text, this.file);
    const sub = ast.subShaders[0];
    if (!sub) throw new Error(`${this.file}: 没有 SubShader`);
    this.files = new Set([this.file]);
    const passes = [];
    for (const p of sub.passes) {
      if (p.usePass) {
        const i = p.usePass.lastIndexOf('/');
        const other = this.lib.getLoaded(p.usePass.slice(0, i)) || this.buildOther(p.usePass.slice(0, i));
        const op = other && other.passes.find((x) => (x.name || '').toUpperCase() === p.usePass.slice(i + 1).toUpperCase());
        if (!op) throw new Error(`${this.file}: UsePass "${p.usePass}" 找不到`);
        passes.push(op);
        other.files.forEach((f) => this.files.add(f));
        continue;
      }
      passes.push({
        name: p.name, tags: p.tags, state: p.state, code: p.code, line: p.line, owner: this,
        include: [...ast.include, ...sub.include],
        lightMode: p.tags.LightMode || 'SRPDefaultUnlit',
      });
    }
    // 关键字声明 + 依赖的 include 文件
    const allCode = [...ast.include, ...sub.include, ...sub.passes.filter((p) => p.code).map((p) => p.code)].map((c) => c.code).join('\n');
    this.declaredKeywords = new Set(findKeywords(allCode).flat());
    this.keywordGroups = findKeywords(allCode).filter((g) => g.length > 1);   // 同一行声明的一组关键字互斥
    const addIncludes = (code) => findIncludes(code).forEach((f) => { if (!this.files.has(f)) { this.files.add(f); const t = this.lib.texts.get(f); if (t) addIncludes(t); } });
    addIncludes(allCode);
    for (const p of passes) if (p.owner === this) p.keywords = this.declaredKeywords;
    this.ast = ast;
    this.tags = sub.tags;
    this.passes = passes;
    this.queue = queueFromTag(sub.tags.Queue);
    this.programs.clear();
    this.version++;
  }

  buildOther(name) {
    const file = this.lib.fileFor(name);
    if (!file || !this.lib.texts.has(file)) return null;
    const sh = new Shader(this.lib, name, file);
    sh.build();
    this.lib.shaders.set(name, sh);
    return sh;
  }

  findPass(lightModeOrName) {
    return this.passes.find((p) => p.lightMode === lightModeOrName) || this.passes.find((p) => (p.name || '').toUpperCase() === String(lightModeOrName).toUpperCase());
  }

  // 编译（并缓存）某个 Pass 在给定关键字下的程序
  program(pass, keywords, extraDefines = '') {
    const owner = pass.owner;
    let kws = [...keywords].filter((k) => owner.declaredKeywords.has(k));
    // 和 Unity 一样：同一组（如 shader_feature _A _B）里材质同时开了多个，变体只能含其中一个——取声明在前的那个
    for (const g of owner.keywordGroups || []) { const on = g.filter((k) => kws.includes(k)); if (on.length > 1) kws = kws.filter((k) => !on.slice(1).includes(k)); }
    kws.sort();
    const key = `${owner.version}|${owner.name}|${pass.name}|${pass.line}|${kws.join(' ')}|${extraDefines}`;
    let prog = owner.programs.get(key);
    if (prog) return prog;
    const lib = owner.lib;
    const src = (stage) => {
      const sb = new SourceBuilder((p) => lib.include(p));
      const defines = [...kws, ...GLOBAL_KEYWORDS].map((k) => `#define ${k} 1`).join('\n');
      sb.add(PRECISION + defines + '\n' + extraDefines + '\n' + STAGE_PRELUDE[stage], `<${stage}>`, 1);
      sb.add(lib.core, 'engine/glsl/Core.glsl', 1);
      sb.add(lib.lighting, 'engine/glsl/Lighting.glsl', 1);
      for (const inc of pass.include) sb.add(inc.code, owner.file, inc.line);
      if (!pass.code) throw new Error(`${owner.file}: Pass ${pass.name} 没有 GLSLPROGRAM`);
      sb.add(pass.code.code, owner.file, pass.code.line);
      // 第一行必须是 #version：去掉开头的 #line
      const s = sb.toString().replace(/^#line[^\n]*\n/, '');
      return { s, files: sb.files };
    };
    const vs = src('VERTEX'), fs = src('FRAGMENT');
    try {
      prog = owner.lib.glc.program(vs.s, fs.s, ATTRIBS);
    } catch (e) {
      if (e instanceof ShaderError) {
        const files = e.stage === 'fragment' ? fs.files : vs.files;
        const errs = mapErrors(e.log, files);
        const err = new Error(errs.map((x) => `${x.file}:${x.line}: ${x.message}`).join('\n') || e.message);
        err.errors = errs.map((x) => ({ ...x, stage: e.stage }));
        err.shader = owner.name;
        throw err;
      }
      throw e;
    }
    owner.programs.set(key, prog);
    return prog;
  }
}

export function queueFromTag(q) {
  if (!q) return 2000;
  const m = /^(Background|Geometry|AlphaTest|Transparent|Overlay)([+-]\d+)?$/.exec(q);
  if (!m) return parseInt(q, 10) || 2000;
  return { Background: 1000, Geometry: 2000, AlphaTest: 2450, Transparent: 3000, Overlay: 4000 }[m[1]] + (m[2] ? parseInt(m[2], 10) : 0);
}

// ---------------- 材质 ----------------
export class Material {
  constructor(shader, json = null) {
    this.shader = shader;
    this.name = json?.name || shader.name;
    this.props = new Map();
    this.keywords = new Set(json?.keywords || []);
    this.queue = json?.queue ?? -1;
    this.disabledPasses = new Set(json?.disabledPasses || []);
    this.textures = new Map();    // 名字 → GL 贴图对象（由 Scene 加载后填入）
    // 先填 shader 默认值，再覆盖导出的值
    for (const p of shader.meta.props || []) {
      if (p.type === 'Texture') this.props.set(p.name, { texture: null, st: [1, 1, 0, 0], default: p.default });
      else if (p.type === 'Color') this.props.set(p.name, isHdr(p) ? p.default.slice() : linearColor(p.default));
      else this.props.set(p.name, Array.isArray(p.default) ? p.default.slice() : p.default);
    }
    if (json) for (const [k, v] of Object.entries(json.props || {})) {
      const cur = this.props.get(k);
      if (v && typeof v === 'object' && !Array.isArray(v)) this.props.set(k, { ...(cur || {}), ...v });
      else this.props.set(k, v);
    }
  }

  get renderQueue() { return this.queue >= 0 ? this.queue : this.shader.queue; }

  setFloat(n, v) { this.props.set(n, v); }
  setVector(n, v) { this.props.set(n, v); }
  // 和 Unity 一样：普通 Color 属性传 sRGB 颜色、上传时转线性；[HDR] 的 Color 原样使用（本来就是线性值）
  setColor(n, c) { const p = (this.shader.meta.props || []).find((x) => x.name === n); this.props.set(n, p && p.type === 'Color' && !isHdr(p) ? linearColor(c) : c.slice()); }   // 未在 Properties 里声明的属性 Unity 原样上传
  setTexture(n, tex) { const p = this.props.get(n) || { st: [1, 1, 0, 0] }; this.props.set(n, { ...p, glTexture: tex }); }
  enableKeyword(k) { this.keywords.add(k); }
  disableKeyword(k) { this.keywords.delete(k); }
  setKeyword(k, on) { on ? this.keywords.add(k) : this.keywords.delete(k); }
  getFloat(n) { const v = this.props.get(n); return typeof v === 'number' ? v : Array.isArray(v) ? v[0] : 0; }

  clone() {
    const m = new Material(this.shader);
    m.name = this.name;
    for (const [k, v] of this.props) m.props.set(k, v && typeof v === 'object' && !Array.isArray(v) ? { ...v } : Array.isArray(v) ? v.slice() : v);
    m.keywords = new Set(this.keywords);
    m.queue = this.queue;
    m.disabledPasses = new Set(this.disabledPasses);
    return m;
  }
}

export function isHdr(p) { return /\bHDR\b/.test(p.flags || ''); }

export function linearColor(c) {
  if (!c) return [0, 0, 0, 1];
  return [srgbToLinear(c[0]), srgbToLinear(c[1]), srgbToLinear(c[2]), c[3] ?? 1];
}
export function srgbColor(c) {
  return [linearToSrgb(c[0]), linearToSrgb(c[1]), linearToSrgb(c[2]), c[3] ?? 1];
}
