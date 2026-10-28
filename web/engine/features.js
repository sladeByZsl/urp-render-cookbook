// Renderer Feature：C# 的 ScriptableRendererFeature 在网页里对应一个 JS 模块。
//   features/<C# 类型全名>.js  导出 default class，形如：
//     export default class {
//       constructor(engine, data, scene) {}          // data = 导出的序列化字段（settings 等）
//       async init() {}                              // 预加载着色器、建材质
//       addPasses(frame, enqueue) { enqueue(RenderPassEvent.AfterRenderingOpaques, (frame) => { ... }); }
//     }
// URP 自带的 RenderObjects 在本文件实现。
import { Material } from './shader.js';

export const RenderPassEvent = {
  BeforeRendering: 0, BeforeRenderingShadows: 50, AfterRenderingShadows: 100, BeforeRenderingPrePasses: 150, AfterRenderingPrePasses: 200,
  BeforeRenderingGbuffer: 210, AfterRenderingGbuffer: 220, BeforeRenderingDeferredLights: 230, AfterRenderingDeferredLights: 240,
  BeforeRenderingOpaques: 250, AfterRenderingOpaques: 300, BeforeRenderingSkybox: 350, AfterRenderingSkybox: 400,
  BeforeRenderingTransparents: 450, AfterRenderingTransparents: 500, BeforeRenderingPostProcessing: 550, AfterRenderingPostProcessing: 600, AfterRendering: 1000,
};

const BUILTIN = {
  'UnityEngine.Experimental.Rendering.Universal.RenderObjects': () => RenderObjects,
};

const moduleCache = new Map();

export async function loadFeature(engine, f, scene) {
  let Cls = BUILTIN[f.type] && BUILTIN[f.type]();
  if (!Cls) {
    const url = engine.assets.url(`features/${f.type}.js`);
    if (!moduleCache.has(url)) moduleCache.set(url, import(url).catch((e) => { moduleCache.delete(url); throw new Error(`Renderer Feature ${f.type} 还没有网页版（${e.message}）`); }));
    Cls = (await moduleCache.get(url)).default;
  }
  const impl = new Cls(engine, f.data, scene, f);
  if (impl.init) await impl.init();
  return impl;
}

// 从导出数据里取材质（Feature 的 settings 里引用的材质会以 {material: id} 形式出现，id 指向场景材质表）
export function featureMaterial(scene, ref) {
  if (!ref) return null;
  const id = ref.material || ref;
  return scene.materialById(id) || null;
}

// 读取导出数据里的 LayerMask（{m_Bits: n}）
export function layerMask(v) {
  if (v === undefined || v === null) return -1;
  if (typeof v === 'number') return v;
  return v.m_Bits ?? -1;
}

// ---------------- URP 内置：RenderObjects ----------------
class RenderObjects {
  constructor(engine, data, scene) {
    this.engine = engine;
    this.data = data;
    this.scene = scene;
    this.s = data.settings || {};
  }
  async init() {
    const ov = this.s.overrideMaterial;
    this.override = ov ? featureMaterial(this.scene, ov) : null;
    // Override Mode：0 None，1 Material，2 Shader（URP 14 起；旧数据没有这个字段时按“有材质就用材质”）
    const sh = this.s.overrideShader;
    if (this.s.overrideMode === 2 && sh && sh.shader) { this.override = null; this.overrideShader = await this.engine.shaders.get(sh.shader); }
    else if (this.s.overrideMode === 0) this.override = null;
  }
  addPasses(frame, enqueue) {
    const s = this.s, fs = s.filterSettings || {};
    const tags = (fs.PassNames || []).filter(Boolean);
    const lightModes = tags.length ? tags : ['SRPDefaultUnlit', 'UniversalForward', 'UniversalForwardOnly'];
    const queue = fs.RenderQueueType === 1 ? 'transparent' : 'opaque';
    const state = {};
    if (s.overrideDepthState) { state.zwrite = s.enableWrite ? 'On' : 'Off'; state.ztest = ['Disabled', 'Never', 'Less', 'Equal', 'LEqual', 'Greater', 'NotEqual', 'GEqual', 'Always'][s.depthCompareFunction ?? 4]; }
    const st = s.stencilSettings;
    if (st && st.overrideStencilState) {
      state.stencil = { Ref: st.stencilReference, Comp: st.stencilCompareFunction, Pass: st.passOperation, Fail: st.failOperation, ZFail: st.zFailOperation, ReadMask: 255, WriteMask: 255 };
    }
    enqueue(s.Event ?? RenderPassEvent.AfterRenderingOpaques, (fr) => {
      fr.bindCamera();
      fr.drawRenderers({
        queue, lightModes, layerMask: layerMask(fs.LayerMask),
        overrideMaterial: this.override, overrideShader: this.overrideShader || null,
        overridePass: this.overrideShader ? (s.overrideShaderPassIndex || 0) : (s.overrideMaterialPassIndex || 0),
        state: Object.keys(state).length ? state : null,
      });
    });
  }
}

export { Material };
