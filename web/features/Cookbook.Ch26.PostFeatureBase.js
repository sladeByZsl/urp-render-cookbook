// 26.3 节：把每个后处理都要重复的部分抽成基类（对应 Ch26/PostFeatureBase.cs）。场景里不会直接用到它，
// 第 26 章其它 Feature 的网页版都 import 这里。
//   PostFeatureBase —— 管 Shader→材质、跳过没开后处理的相机、按 Volume 是否启用决定入队。
//   PostPassBase    —— 管 RT 分配工具、执行后恢复渲染目标。
//   SimplePostPass  —— 最常见的“相机颜色 →(材质)→ 临时 RT → 拷回相机颜色”。
// 另外提供 defineVolume：自定义 Volume 组件的默认值（C# 里参数构造时的值）要登记到 VOLUME_DEFAULTS，
// 这样 Volume 权重 < 1 时才能像 Unity 一样在“默认值 ↔ 覆盖值”之间插值。
import { Material } from '../engine/shader.js';
import { RenderPassEvent } from '../engine/features.js';
import { VOLUME_DEFAULTS } from '../engine/post.js';

// ScriptableRenderPassInput
export const PassInput = { None: 0, Depth: 1, Normal: 2, Color: 4, Motion: 8 };

export function defineVolume(type, defaults) { VOLUME_DEFAULTS[type] = defaults; }

// VolumeManager.instance.stack.GetComponent<T>()：没有任何 Volume 提供该组件时返回默认值
export function stackComponent(frame, type) { return frame.getVolume(type) || { ...VOLUME_DEFAULTS[type] }; }

//#region feature-base
export class PostFeatureBase {
  constructor(engine, data, scene) {
    this.engine = engine;
    this.scene = scene;
    this.data = data || {};
    this.passEvent = this.data.passEvent ?? RenderPassEvent.BeforeRenderingPostProcessing;
  }

  get shaderName() { throw new Error('子类要实现 shaderName'); }
  createPass(material) { throw new Error('子类要实现 createPass'); }

  async init() {
    // shader 留空则按 ShaderName 查找
    const name = (this.data.shader && this.data.shader.shader) || this.shaderName;
    this.material = new Material(await this.engine.shaders.get(name));
    this.pass = this.createPass(this.material);
  }

  addPasses(frame, enqueue) {
    if (!this.pass) return;
    if (!frame.camera.postProcessing) return;          // 相机没勾 Post Processing 就不做
    // Prepare：读 Volume、写材质常量；返回 false 表示本帧无效果
    if (!this.pass.prepare(frame)) return;
    // ConfigureInput：深度/法线等输入必须在入队前声明
    const req = this.pass.requiredInputs;
    if (req & PassInput.Depth) frame.requireDepth = true;
    if (req & PassInput.Color) frame.requireOpaque = true;
    if (req & PassInput.Normal && this.pass.renderNormals) {
      // 前向路径下，Normal 输入会让 URP 在不透明物体之前多跑一遍 DepthNormals 预渲染
      enqueue(RenderPassEvent.BeforeRenderingOpaques, (fr) => this.pass.renderNormals(fr), 'DepthNormalPrepass');
    }
    enqueue(this.passEvent, (fr) => {
      this.pass.render(fr);
      fr.bindCamera();                                  // 还给 URP 一个“原样”的目标
    }, this.pass.name);
  }
}
//#endregion

//#region pass-base
export class PostPassBase {
  constructor(material, name) { this.material = material; this.name = name; }
  get requiredInputs() { return PassInput.None; }
  prepare(frame) { return false; }
  render(fr) {}

  // 相机颜色同格式、去掉 MSAA 与深度、按 downsample 缩小的临时 RT
  static colorRT(fr, name, downsample = 1) {
    return fr.getTemporaryRT(name, Math.max(1, Math.floor(fr.width / downsample)), Math.max(1, Math.floor(fr.height / downsample)));
  }
}
//#endregion

//#region simple-pass
export class SimplePostPass extends PostPassBase {
  constructor(material, name, volumeType) { super(material, name); this.volumeType = volumeType; }
  isActive(v) { return false; }
  apply(v, frame) {}

  prepare(frame) {
    const v = frame.getVolume(this.volumeType);
    if (!v || !this.isActive(v)) return false;
    this.apply(v, frame);
    return true;
  }

  render(fr) {
    const temp = PostPassBase.colorRT(fr, '_Ch26Temp_' + this.volumeType.split('.').pop());
    fr.blit(fr.cameraColorTexture(), temp, this.material, 0);
    fr.blit(temp.texture, 'camera');
  }
}
//#endregion

// 第 26 章：深度 + 法线 预渲染（_CameraNormalsTexture），给需要 Normal 输入的 Pass 用。
// 和 URP 一样，有了这个预渲染，_CameraDepthTexture 也取自它（不带 MSAA，与法线逐像素对齐），
// 返回的 rt.depthTexture 由调用者在读深度前设成 _CameraDepthTexture。
export function renderDepthNormals(fr) {
  const gl = fr.gl;
  const rt = fr.getTemporaryRT('_CameraNormalsTexture', fr.width, fr.height, { color: 'RGBA16F', depth: 'DEPTH24' });
  fr.engine.bindTarget(rt);
  gl.colorMask(true, true, true, true); gl.depthMask(true);
  gl.clearColor(0, 0, 0, 0); gl.clearDepth(1);
  gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
  fr.drawRenderers({ queue: 'opaque', lightModes: ['DepthNormals', 'DepthNormalsOnly'], layerMask: fr.scene.rendererData.m_OpaqueLayerMask ?? -1 });
  fr.setGlobal('_CameraNormalsTexture', rt.texture);
  fr.bindCamera();
  return rt;
}
