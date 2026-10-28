// 第 2 章 案例 2.1：帧快照 Renderer Feature（JS 版，对应 Ch02/FrameSnapshotFeature.cs）
// 在 captureEvent 这个时间点，把相机颜色缓冲“拍”一张快照；
// 在后处理之后，再把快照贴回相机颜色缓冲。于是屏幕上看到的，就是这一帧在 captureEvent 时刻的“半成品”。
import { RenderPassEvent } from '../engine/features.js';

export default class FrameSnapshotFeature {
  constructor(engine, data) {
    this.engine = engine;
    this.captureEvent = data.captureEvent ?? RenderPassEvent.AfterRenderingOpaques;   // 在哪个时间点拍快照
    this.clearColorBeforeOpaques = data.clearColorBeforeOpaques ?? true;               // 画不透明物体之前把颜色清成黑色
  }

  addPasses(frame, enqueue) {
    const E = this.engine, gl = E.gl;
    let snapshot = null;

    // ClearColorPass：此时相机颜色/深度缓冲已经绑定，只清颜色
    if (this.clearColorBeforeOpaques) {
      enqueue(RenderPassEvent.BeforeRenderingOpaques, (fr) => {
        fr.bindCamera();
        gl.colorMask(true, true, true, true);
        gl.clearColor(0, 0, 0, 1);
        gl.clear(gl.COLOR_BUFFER_BIT);
      }, 'Cookbook Snapshot Clear');
    }

    // CapturePass：快照格式与相机颜色缓冲一致（HDR 时是浮点），不要深度、不要 MSAA。
    // cameraColorTexture() 会先把多重采样缓冲解析（resolve）出来，读到的才是此刻的画面
    enqueue(this.captureEvent, (fr) => {
      const rt = fr.getTemporaryRT('_FrameSnapshot', fr.width, fr.height, { color: fr.colorFormat });
      fr.blit(fr.cameraColorTexture(), rt, E.blitMat, 'Copy');
      snapshot = rt.texture;
      fr.bindCamera();
    }, 'Cookbook Snapshot Capture');

    // RestorePass：后处理之后、FinalBlit 之前，把快照贴回“当前”的相机颜色（后处理开启时就是后处理的输出）
    enqueue(RenderPassEvent.AfterRenderingPostProcessing, (fr) => {
      if (!snapshot) return;
      if (fr.postDone) fr.postOutput = snapshot;
      else { fr.blit(snapshot, 'camera', E.blitMat, 'Copy'); fr.bindCamera(); }
    }, 'Cookbook Snapshot Restore');
  }
}
