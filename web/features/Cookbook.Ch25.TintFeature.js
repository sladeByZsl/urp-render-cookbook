// 案例 25.1 / 25.2：TintFeature 的网页版（对应 Ch25/TintFeature.cs）。
// 结构和 C# 一样：Feature 负责建材质、按 settings.passEvent 入队；Pass 负责“相机颜色 →(材质)→ 临时 RT → 拷回相机颜色”。
import { Material } from '../engine/shader.js';
import { RenderPassEvent } from '../engine/features.js';

export default class TintFeature {
  constructor(engine, data, scene) {
    this.engine = engine;
    this.scene = scene;
    this.data = data || {};
    // C# Settings 的默认值
    this.settings = { passEvent: RenderPassEvent.BeforeRenderingPostProcessing, tint: [1, 1, 1, 1], invert: 1, desaturate: 0, ...(this.data.settings || {}) };
  }

  async init() {
    // Create()：shader 留空时退回 Shader.Find("Cookbook/Ch25/Tint")
    const name = (this.data.shader && this.data.shader.shader) || 'Cookbook/Ch25/Tint';
    this.material = new Material(await this.engine.shaders.get(name));
  }

  addPasses(frame, enqueue) {
    if (!this.material) return;
    const s = this.settings, m = this.material;
    // TintPass.Setup：这些值在一帧内不变，直接写材质
    // 注意：C# 的 material.SetColor 写的是 Properties 块里没声明的属性，Unity 原样上传、不做 sRGB→线性（和书中图实测一致），所以用 setVector
    m.setVector('_TintColor', s.tint);
    m.setFloat('_Invert', s.invert);
    m.setFloat('_Desaturate', s.desaturate);
    enqueue(s.passEvent, (fr) => {
      // OnCameraSetup：临时 RT 和相机颜色同尺寸、同格式，不要 MSAA、不要深度
      const temp = fr.getTemporaryRT('_Ch25TintTemp', fr.width, fr.height);
      // 不能边读边写同一张纹理：先“相机颜色 → 临时 RT（经过材质）”，再拷回
      fr.blit(fr.cameraColorTexture(), temp, m, 0);
      fr.blit(temp.texture, 'camera');
      // 恢复相机的颜色 + 深度目标
      fr.bindCamera();
    }, 'Ch25 Tint');
  }
}
