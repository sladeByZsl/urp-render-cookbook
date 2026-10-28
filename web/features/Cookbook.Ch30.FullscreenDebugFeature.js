// 第 30 章的全屏调试 Feature 的网页版（对应 Ch30/FullscreenDebugFeature.cs）：
// 把相机颜色拷贝一份，再用调试材质（像素校验等）画回去。
import { RenderPassEvent, featureMaterial } from '../engine/features.js';

export default class FullscreenDebugFeature {
  constructor(engine, data, scene) {
    this.engine = engine;
    this.scene = scene;
    // C# Settings 的默认值
    this.settings = { material: null, passIndex: 0, renderPassEvent: RenderPassEvent.BeforeRenderingPostProcessing, requirements: 0, ...((data && data.settings) || {}) };
  }

  async init() {
    this.material = featureMaterial(this.scene, this.settings.material);
  }

  addPasses(frame, enqueue) {
    const s = this.settings;
    if (!this.material) return;
    enqueue(s.renderPassEvent, (fr) => {
      // 网页版的后处理输出是一张单独的贴图（frame.postOutput）：AfterRenderingPostProcessing 且开了后处理时，读写它
      const afterPost = s.renderPassEvent >= RenderPassEvent.AfterRenderingPostProcessing && fr.postDone;
      const src = afterPost ? fr.postOutput : fr.cameraColorTexture();
      // 临时 RT 与相机目标同尺寸、同格式，但不要 MSAA、不要深度
      const copy = fr.getTemporaryRT('_FullscreenDebugCopy', fr.width, fr.height);
      // 不能边读边写同一张 RT：先拷贝，再以拷贝为 _BlitTexture 画回去
      fr.blit(src, copy);
      if (afterPost) {
        const out = fr.getTemporaryRT('_FullscreenDebugOut', fr.width, fr.height, { color: 'RGBA16F' });
        fr.blit(copy.texture, out, this.material, s.passIndex);
        fr.postOutput = out.texture;
      } else fr.blit(copy.texture, 'camera', this.material, s.passIndex);
      fr.bindCamera();
    }, 'FullscreenDebug');
  }
}
