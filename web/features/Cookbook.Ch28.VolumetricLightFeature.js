// 案例 28.5：体积光 Renderer Feature（对应 Ch28/VolumetricLightFeature.cs）—— 半分辨率光线步进 → 模糊 → 合成。
import { featureMaterial, RenderPassEvent } from '../engine/features.js';
import { ensureDepth } from './Cookbook.Ch28.ScreenSpaceUtil.js';

const Output = { Composite: 0, ScatterOnly: 1 };

export default class VolumetricLightFeature {
  constructor(engine, data, scene) {
    this.engine = engine;
    this.scene = scene;
    this.settings = { material: null, downsample: 2, blur: true, output: Output.Composite, renderPassEvent: RenderPassEvent.BeforeRenderingTransparents, ...((data && data.settings) || {}) };
  }

  async init() { this.material = featureMaterial(this.scene, this.settings.material); }

  addPasses(frame, enqueue) {
    const s = this.settings, mat = this.material;
    if (!mat) return;
    // 没有主光阴影就没有“光束”，直接跳过
    if (frame.scene.asset.m_MainLightShadowsSupported === false) return;
    enqueue(s.renderPassEvent, (fr) => {
      ensureDepth(fr);   // ConfigureInput(Depth)
      const ds = Math.max(1, s.downsample | 0);
      const w = Math.max(1, Math.floor(fr.width / ds)), h = Math.max(1, Math.floor(fr.height / ds));
      // 散射值可能 >1，用半精度浮点
      const vol = fr.getTemporaryRT('_Volumetric', w, h, { color: 'RGBA16F' });
      const volTemp = fr.getTemporaryRT('_VolumetricTemp', w, h, { color: 'RGBA16F' });
      mat.setVector('_VolTexelSize', [1 / w, 1 / h, w, h]);
      fr.blit(null, vol, mat, 0);                       // 光线步进
      if (s.blur) {
        fr.blit(vol.texture, volTemp, mat, 1);          // 横向模糊
        fr.blit(volTemp.texture, vol, mat, 2);          // 纵向模糊
      }
      fr.setGlobal('_VolumetricResult', vol.texture);
      const copy = fr.getTemporaryRT('_VolumetricColorCopy', fr.width, fr.height, { filter: 'Point' });
      fr.blit(fr.cameraColorTexture(), copy);
      fr.blit(copy.texture, 'camera', mat, s.output === Output.Composite ? 3 : 4);
      fr.bindCamera();
    }, 'VolumetricLight');
  }
}
