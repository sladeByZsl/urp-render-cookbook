// 27.17 节配图用的 MotionBlurPreviewFeature（对应 Ch27/MotionBlurPreviewFeature.cs）。
// 直接调用 URP 自带的 Hidden/Universal Render Pipeline/CameraMotionBlur（网页版见 shaders/URP/CameraMotionBlur.glsl），
// “上一帧的 VP 矩阵”由外部指定（导出数据里的 previousViewProj）。
import { RenderPassEvent } from '../engine/features.js';
import { cameraMotionBlur } from '../engine/post/extra.js';

export default class MotionBlurPreviewFeature {
  constructor(engine, data) {
    this.engine = engine;
    this.data = { intensity: 0.5, clamp: 0.05, quality: 2, ...(data || {}) };
    // C# 里是 GL.GetGPUProjectionMatrix(P, true) * V：渲染到贴图时 y 被翻转（D3D/Metal 约定）。
    // WebGL 不翻转，所以把第 2 行取反还原；z 行不影响屏幕速度，可以不管。
    const e = this.data.previousViewProj;
    const m = new Float32Array(16);
    if (e && e.e00 !== undefined) {
      for (let r = 0; r < 4; r++) for (let c = 0; c < 4; c++) m[c * 4 + r] = e[`e${r}${c}`];
      for (let c = 0; c < 4; c++) m[c * 4 + 1] = -m[c * 4 + 1];
    } else m.set([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);
    this.prevViewProj = m;
  }

  addPasses(frame, enqueue) {
    const s = this.data;
    if (!(s.intensity > 0)) return;
    // 与 URP 一样：在后处理（色调映射）之前，作用于 HDR 颜色
    enqueue(RenderPassEvent.BeforeRenderingPostProcessing, (fr) => {
      const temp = cameraMotionBlur(this.engine, fr, fr.cameraColorTexture(), {
        viewProj: fr.viewProj, prevViewProj: this.prevViewProj, intensity: s.intensity, clamp: s.clamp, quality: s.quality, depth: fr.cameraDepthTexture(),
      });
      fr.blit(temp.texture, 'camera');
      fr.bindCamera();
    }, 'MotionBlurPreview');
  }
}
