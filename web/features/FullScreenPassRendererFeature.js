// URP 14 自带的 Full Screen Pass Renderer Feature 的网页版。
// 序列化字段：injectionPoint（RenderPassEvent）、fetchColorBuffer、requirements（Depth=1, Normal=2, Color=4, Motion=8）、passMaterial、passIndex。
// fetchColorBuffer 时先把相机颜色拷一份，作为 _BlitTexture 传给材质，再用全屏三角形画回相机颜色。
import { featureMaterial, RenderPassEvent } from '../engine/features.js';

export default class FullScreenPassRendererFeature {
  constructor(engine, data, scene) {
    this.engine = engine;
    this.data = { injectionPoint: RenderPassEvent.AfterRenderingPostProcessing, fetchColorBuffer: true, requirements: 0, passIndex: 0, ...(data || {}) };
    this.material = featureMaterial(scene, this.data.passMaterial);
  }

  addPasses(frame, enqueue) {
    const d = this.data, m = this.material;
    if (!m) return;
    // ConfigureInput(requirements)
    if (d.requirements & 1) frame.requireDepth = true;
    if (d.requirements & 4) frame.requireOpaque = true;
    enqueue(d.injectionPoint, (fr) => {
      let src = null;
      if (d.fetchColorBuffer) {
        const copy = fr.getTemporaryRT('_FullscreenPassColorCopy', fr.width, fr.height);
        fr.blit(fr.cameraColorTexture(), copy);
        src = copy.texture;
      }
      fr.blit(src, 'camera', m, d.passIndex || 0);
      fr.bindCamera();
    }, 'FullScreenPass');
  }
}
