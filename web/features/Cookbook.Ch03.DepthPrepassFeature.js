// 演示用 Renderer Feature（JS 版，对应 Ch03/DepthPrepassFeature.cs）：
// 声明“我在不透明物体之前就要用深度图”，从而让 URP 走深度预渲染（Depth Prepass）。
// 这时 _CameraDepthTexture 由各物体的 DepthOnly Pass 画出来——没有 DepthOnly Pass 的物体就不在深度图里。
// C# 版的 Pass 本身什么都不画，只用 ConfigureInput(Depth) 提需求；网页引擎没有“按需求自动加 Prepass”的机制，
// 所以这里把 URP 因此插入的 DepthPrepass 一起做了：在 BeforeRenderingPrePasses 时把不透明物体的 DepthOnly Pass 画进一张深度图。
import { RenderPassEvent } from '../engine/features.js';

export default class DepthPrepassFeature {
  constructor(engine) { this.engine = engine; }

  addPasses(frame, enqueue) {
    const E = this.engine, gl = E.gl;
    enqueue(RenderPassEvent.BeforeRenderingPrePasses, (fr) => {
      const rt = E.rt('cookbook:depthPrepass', fr.width, fr.height, { color: null, depth: 'DEPTH24' });
      E.bindTarget(rt);
      gl.depthMask(true); gl.clearDepth(1); gl.clear(gl.DEPTH_BUFFER_BIT);
      fr.drawRenderers({ queue: 'opaque', lightModes: ['DepthOnly'] });
      E.setGlobal('_CameraDepthTexture', rt.depthTexture);
      // 有了 Prepass，URP 就不再在不透明物体之后 CopyDepth
      fr.requireDepth = false;
      fr.bindCamera();
    }, 'DepthPrepass');
  }
}
