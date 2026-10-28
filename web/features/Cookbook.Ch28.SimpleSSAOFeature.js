// 案例 28.4：简化版 SSAO 的 Renderer Feature（对应 Ch28/SimpleSSAOFeature.cs）。
//   IntoLighting        —— 像 URP 自带 SSAO 一样，在不透明物体之前算好 AO，作为 _ScreenSpaceOcclusionTexture 交给光照；
//   MultiplyAfterOpaque —— 不透明物体画完后直接把 AO 乘到颜色上；
//   ShowAO              —— 只显示 AO（调试）。
import { featureMaterial, RenderPassEvent } from '../engine/features.js';
import { renderDepthNormals } from './Cookbook.Ch28.ScreenSpaceUtil.js';

const Mode = { IntoLighting: 0, MultiplyAfterOpaque: 1, ShowAO: 2 };

export default class SimpleSSAOFeature {
  constructor(engine, data, scene) {
    this.engine = engine;
    this.scene = scene;
    this.settings = { material: null, mode: Mode.IntoLighting, blur: true, halfResolution: false, directLightingStrength: 0.25, ...((data && data.settings) || {}) };
  }

  async init() { this.material = featureMaterial(this.scene, this.settings.material); }

  addPasses(frame, enqueue) {
    const s = this.settings, mat = this.material;
    if (!mat) return;
    //#region event
    // 进光照：必须在不透明物体之前，且要等深度/法线预通道画完（+1 与 URP 自带 SSAO 一致）
    const event = s.mode === Mode.IntoLighting ? RenderPassEvent.AfterRenderingPrePasses + 1 : RenderPassEvent.AfterRenderingOpaques;
    //#endregion
    // ConfigureInput(Depth | Normal)：前向路径下 URP 会执行 DepthNormals 预通道
    enqueue(RenderPassEvent.AfterRenderingPrePasses, (fr) => renderDepthNormals(fr), 'DepthNormalPrepass');
    enqueue(event, (fr) => {
      const W = s.halfResolution ? Math.floor(fr.width / 2) : fr.width, H = s.halfResolution ? Math.floor(fr.height / 2) : fr.height;
      const ao = fr.getTemporaryRT('_SimpleSSAO', W, H, { color: 'RGBA8' });
      const aoTemp = fr.getTemporaryRT('_SimpleSSAOTemp', W, H, { color: 'RGBA8' });
      mat.setVector('_SSAOTexelSize', [1 / W, 1 / H, W, H]);
      // 1) AO：没有输入纹理，直接画全屏三角形
      fr.blit(null, ao, mat, 0);
      // 2) 可分离双边模糊：AO → Temp（横）→ AO（竖）
      if (s.blur) {
        fr.blit(ao.texture, aoTemp, mat, 1);
        fr.blit(aoTemp.texture, ao, mat, 2);
      }
      if (s.mode === Mode.IntoLighting) {
        // 3a) 按 URP 的约定把结果交给光照：纹理 + 参数（w = 直接光受 AO 影响的比例）
        fr.setGlobal('_ScreenSpaceOcclusionTexture', ao.texture);
        fr.setGlobal('_AmbientOcclusionParam', [1, 0, 0, s.directLightingStrength]);
      } else {
        // 3b) 直接乘到相机颜色上（或只显示 AO）
        fr.setGlobal('_SSAOResult', ao.texture);
        const copy = fr.getTemporaryRT('_SimpleSSAOColor', fr.width, fr.height, { filter: 'Point' });
        fr.blit(fr.cameraColorTexture(), copy);
        fr.blit(copy.texture, 'camera', mat, s.mode === Mode.ShowAO ? 4 : 3);
      }
      fr.bindCamera();
    }, 'SimpleSSAO');
  }
}
