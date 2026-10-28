// 案例 29.5：Overdraw 可视化 Renderer Feature 的网页版（对应 Ch29/OverdrawFeature.cs）。
// 用 overrideMaterial 把可见物体全部重画一遍到一张 R16 浮点 RT（每层 +1），再用热度图画回相机颜色。
import { RenderPassEvent, featureMaterial, layerMask } from '../engine/features.js';

// 和 URP 自己画不透明/透明物体时用的 LightMode 列表一致
const TAGS = ['UniversalForward', 'UniversalForwardOnly', 'SRPDefaultUnlit', 'LightweightForward'];

export default class OverdrawFeature {
  constructor(engine, data, scene) {
    this.engine = engine;
    this.scene = scene;
    const s = (data && data.settings) || {};
    this.settings = { opaque: true, transparent: true, layerMask: -1, ...s };
  }

  async init() {
    const s = this.settings;
    this.countMaterial = featureMaterial(this.scene, s.countMaterial);       // Cookbook/Ch29/OverdrawCount
    this.heatmapMaterial = featureMaterial(this.scene, s.heatmapMaterial);   // Cookbook/Ch29/OverdrawHeatmap
  }

  addPasses(frame, enqueue) {
    const s = this.settings;
    if (!this.countMaterial || !this.heatmapMaterial) return;
    enqueue(RenderPassEvent.AfterRenderingTransparents, (fr) => {
      const gl = fr.gl, E = this.engine;
      // OnCameraSetup：和相机同尺寸、不要 MSAA 和深度；计数可能超过 1，要浮点格式；点采样
      const count = fr.getTemporaryRT('_OverdrawCount', fr.width, fr.height, { color: 'R16F', filter: 'Point' });
      E.bindTarget(count);
      gl.colorMask(true, true, true, true);
      gl.clearColor(0, 0, 0, 0);
      gl.clear(gl.COLOR_BUFFER_BIT);   // ConfigureClear(ClearFlag.Color, Color.black)
      const mask = layerMask(s.layerMask);
      // Execute：所有物体都用计数材质画（overrideMaterial）
      if (s.opaque) fr.drawRenderers({ queue: 'opaque', lightModes: TAGS, layerMask: mask, overrideMaterial: this.countMaterial, overridePass: 0 });
      if (s.transparent) fr.drawRenderers({ queue: 'transparent', lightModes: TAGS, layerMask: mask, overrideMaterial: this.countMaterial, overridePass: 0, sort: 'backToFront' });
      // Blitter.BlitCameraTexture(cmd, m_Count, m_CameraColor, heatmapMaterial, 0)
      fr.blit(count.texture, 'camera', this.heatmapMaterial, 0);
      fr.bindCamera();
    }, 'OverdrawView');
  }
}
