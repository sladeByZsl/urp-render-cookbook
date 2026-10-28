// 第 28 章通用的“全屏效果” Renderer Feature（对应 Ch28/ScreenEffectFeature.cs）。
// 把相机颜色拷贝到一张临时 RT，再用指定材质的指定 Pass 画回相机颜色。
// 本章的世界坐标重建、扫描线、雾、SSR 都靠它跑，算法全部写在各自的 Shader 里。
import { featureMaterial, RenderPassEvent } from '../engine/features.js';
import { PassInput, renderDepthNormals, ensureDepth } from './Cookbook.Ch28.ScreenSpaceUtil.js';

export default class ScreenEffectFeature {
  constructor(engine, data, scene) {
    this.engine = engine;
    this.scene = scene;
    this.settings = { material: null, passIndex: 0, renderPassEvent: RenderPassEvent.BeforeRenderingPostProcessing, requirements: PassInput.Depth, ...((data && data.settings) || {}) };
  }

  async init() { this.material = featureMaterial(this.scene, this.settings.material); }

  addPasses(frame, enqueue) {
    const s = this.settings, m = this.material;
    if (!m) return;
    // ConfigureInput(Normal)：DepthNormals 预渲染在不透明物体之前
    if (s.requirements & PassInput.Normal) enqueue(RenderPassEvent.BeforeRenderingOpaques, (fr) => renderDepthNormals(fr), 'DepthNormalPrepass');
    enqueue(s.renderPassEvent, (fr) => {
      if (!(s.requirements & PassInput.Normal) && (s.requirements & PassInput.Depth)) ensureDepth(fr);
      // 不能边读边写同一张 RT：先拷贝，再以拷贝为 _BlitTexture 画回去
      const copy = fr.getTemporaryRT('_ScreenEffectCopy', fr.width, fr.height);
      fr.blit(fr.cameraColorTexture(), copy);
      fr.blit(copy.texture, 'camera', m, s.passIndex);
      fr.bindCamera();
    }, 'ScreenEffect');
  }
}
