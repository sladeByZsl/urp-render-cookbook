// 网页版模拟 URP 的 Rendering Debugger（Window › Analysis › Rendering Debugger）“Material”页：
//   materialDebugMode：Albedo / Specular / Alpha / Smoothness / AmbientOcclusion / Emission / NormalWorldSpace / Metallic
//   materialValidationMode：Albedo（亮度过暗标红、过亮标蓝）/ Metallic
// Unity 里调试器是编辑器全局设置（书里的配图脚本用 UniversalRenderPipelineDebugDisplaySettings.Instance.materialSettings 设置），
// 不会出现在导出的场景数据里；网页版把它写成一个“Renderer Feature”挂在需要的配图上（ch11-rd、ch13-rd）。
// 做法与 URP 相同：着色器有 DEBUG_DISPLAY 分支的（如 MyPBR）打开这个关键字重画；URP Lit 用替换着色器
// （shaders/Ch11/LitDebugReplacement.glsl，读 Lit 的同名属性）重画。调试视图不受光照影响，阴影、雾都不画。
import { RenderPassEvent, Material } from '../engine/features.js';

// URP 枚举 DebugMaterialMode / DebugMaterialValidationMode
const MATERIAL_MODES = { None: 0, Albedo: 1, Specular: 2, Alpha: 3, Smoothness: 4, AmbientOcclusion: 5, Emission: 6, NormalWorldSpace: 7, NormalTangentSpace: 8, LightingComplexity: 9, Metallic: 10, SpriteMask: 11 };
const VALIDATION_MODES = { None: 0, Albedo: 1, Metallic: 2 };
const REPLACEMENT = 'Hidden/Cookbook/Ch11/LitDebugReplacement';

export default class DebugDisplaySettings {
  constructor(engine, data, scene) {
    this.engine = engine;
    this.scene = scene;
    const m = (data && data.materialSettings) || {};
    const pick = (v, table) => (typeof v === 'string' ? table[v] ?? 0 : v ?? 0);
    // 默认值与 URP 14 的 DebugDisplaySettingsMaterial 相同
    this.s = {
      materialDebugMode: pick(m.materialDebugMode, MATERIAL_MODES),
      materialValidationMode: pick(m.materialValidationMode, VALIDATION_MODES),
      albedoMinLuminance: m.albedoMinLuminance ?? 0.01,
      albedoMaxLuminance: m.albedoMaxLuminance ?? 0.9,
      metallicMinValue: m.metallicMinValue ?? 0.0,
      metallicMaxValue: m.metallicMaxValue ?? 0.9,
    };
    this.replacements = new Map();
  }

  async init() {
    const lib = this.engine.shaders;
    // 替换着色器不在 Unity 导出的着色器表里（它没有 HLSL 原版），手动登记文件位置
    if (!lib.meta[REPLACEMENT]) lib.meta[REPLACEMENT] = { path: 'Ch11/LitDebugReplacement.shader', props: [], passes: [] };
    this.replacementShader = await lib.get(REPLACEMENT);
  }

  // 用替换着色器 + 原材质的属性与关键字（相当于 Unity 的 Override Shader）
  replacementFor(m) {
    let r = this.replacements.get(m);
    if (!r) {
      r = new Material(this.replacementShader);
      for (const [k, v] of m.props) r.props.set(k, v);
      r.keywords = m.keywords;
      this.replacements.set(m, r);
    }
    return r;
  }

  addPasses(frame, enqueue) {
    const s = this.s;
    if (!s.materialDebugMode && !s.materialValidationMode) return;
    frame.setGlobal('_DebugMaterialMode', s.materialDebugMode);
    frame.setGlobal('_DebugMaterialValidationMode', s.materialDebugMode ? 0 : s.materialValidationMode);
    frame.setGlobal('_DebugValidateAlbedoParams', [s.albedoMinLuminance, s.albedoMaxLuminance, 0, 0]);
    frame.setGlobal('_DebugValidateMetallicParams', [s.metallicMinValue, s.metallicMaxValue, 0, 0]);
    // 不透明物体画完后：清掉相机目标，用调试着色器把不透明物体重画一遍（天空盒随后照常画在空白处）
    enqueue(RenderPassEvent.AfterRenderingOpaques, (fr) => {
      const E = this.engine, gl = fr.gl, cam = fr.camera;
      fr.bindCamera();
      gl.depthMask(true); gl.colorMask(true, true, true, true);
      const bg = cam.clearFlags === 'SolidColor' ? cam.background : [0, 0, 0, 0];
      gl.clearColor(bg[0], bg[1], bg[2], bg[3]); gl.clearDepth(1);
      gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
      for (const o of fr.visibleRenderers()) {
        if (o.renderer.shadowsOnly) continue;
        o.renderer.materials.forEach((m, si) => {
          if (!m || m.renderQueue > 2500) return;
          const forward = m.shader.passes.find((p) => p.lightMode === 'UniversalForward');
          if (!forward) return;
          if (m.shader.declaredKeywords && m.shader.declaredKeywords.has('DEBUG_DISPLAY')) {
            E.draw(o, si, m, forward, { keywords: new Set([...m.keywords, 'DEBUG_DISPLAY']) });
          } else {
            const r = this.replacementFor(m);
            E.draw(o, si, r, r.shader.passes[0]);
          }
        });
      }
      fr.copyDepth();
    }, 'Rendering Debugger');
  }
}
