// URP 自带的 Decal Renderer Feature（网页版，对应 Runtime/Decal/DecalRendererFeature.cs）。
// Technique：0 Automatic（桌面上 = DBuffer）/ 1 DBuffer / 2 Screen Space。
// URP 的 DBuffer 是在不透明物体之前把贴花写进几张 DBuffer，Lit 等 Shader 着色时再读出来；
// 网页版把两种技术都简化为“屏幕空间贴花”：不透明物体画完后，逐个 Decal Projector 画一个投影盒，
// 用深度图重建表面位置、算出贴花 UV，用贴花颜色和表面法线重新计算光照，再按 Alpha 叠到相机颜色上。
//   DBuffer：表面法线来自 DepthNormals 预渲染（保留表面法线贴图，贴花法线可与之混合）
//   Screen Space：表面法线由深度图重建（Normal Blend = Medium 的效果）
import { RenderPassEvent } from '../engine/features.js';
import { mat4 } from '../engine/math.js';

const DECAL_SMOOTHNESS = 0.3;   // 贴花不影响 MAOS 时沿用表面的光滑度；网页版拿不到表面的光滑度，取一个常见值

export default class DecalRendererFeature {
  constructor(engine, data, scene) {
    this.engine = engine; this.scene = scene;
    const s = (data && data.m_Settings) || {};
    this.technique = s.technique ?? 0;
    this.maxDrawDistance = s.maxDrawDistance ?? 1000;
  }

  async init() {
    this.cube = await this.engine.assets.mesh('builtin_Cube');
  }

  addPasses(frame, enqueue) {
    const list = (this.scene.decalProjectors || []).filter((d) => d.enabled && d.obj.active && d.material && !d.material.missing);
    if (!list.length) return;
    const dbuffer = this.technique !== 2;
    // URP 的屏幕空间贴花在 AfterRenderingOpaques 绘制；DBuffer 的结果也在不透明物体里体现，所以都放在这里
    enqueue(RenderPassEvent.AfterRenderingOpaques, (fr) => this.render(fr, list, dbuffer));
  }

  render(fr, list, dbuffer) {
    const E = this.engine, gl = fr.gl, W = fr.width, H = fr.height;
    if (dbuffer) {
      // DepthNormals 预渲染：得到带法线贴图的表面法线（URP 的 DBuffer 技术同样依赖它）
      const rt = fr.getTemporaryRT('DecalDepthNormals', W, H, { color: 'RGBA16F', depth: 'DEPTH24', filter: 'Point' });
      E.bindTarget(rt);
      gl.depthMask(true); gl.colorMask(true, true, true, true);
      gl.clearColor(0, 0, 0, 0); gl.clearDepth(1);
      gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
      fr.drawRenderers({ queue: 'opaque', lightModes: ['DepthNormals'] });
      fr.setGlobal('_CameraNormalsTexture', rt.texture);
    }
    fr.setGlobal('_CameraDepthTexture', fr.cameraDepthTexture());
    fr.bindCamera();
    const lightMode = dbuffer ? 'DBufferProjector' : 'DecalScreenSpaceProjector';
    const cam = fr.cameraPos;
    // 按材质的 Draw Order 排序，同序按登记顺序
    const items = list.map((d, i) => ({ d, i, order: d.material.getFloat ? d.material.getFloat('_DrawOrder') || 0 : 0 }))
      .sort((a, b) => a.order - b.order || a.i - b.i);
    for (const { d } of items) {
      const pass = d.material.shader.passes.find((p) => p.lightMode === lightMode);
      if (!pass) continue;
      const m = d.boxMatrix();
      const pos = [m[12], m[13], m[14]];
      const dist = Math.hypot(pos[0] - cam[0], pos[1] - cam[1], pos[2] - cam[2]);
      const drawDistance = Math.min(d.drawDistance, this.maxDrawDistance);
      if (dist > drawDistance) continue;
      const distFade = Math.min(1, Math.max(0, (drawDistance - dist) / Math.max(1e-4, drawDistance * (1 - d.fadeScale))));
      const af = d.angleFade();
      const obj = { mesh: this.cube, matrix: m, invMatrix: mat4.invert(m), flip: false, uniforms: {} };
      E.draw(obj, 0, d.material, pass, {
        overrides: {
          _DecalParams: [d.fadeFactor * distFade, af[0], af[1], af[2]],
          _DecalUVScaleBias: [d.uvScale[0], d.uvScale[1], d.uvBias[0], d.uvBias[1]],
          _DecalSmoothness: DECAL_SMOOTHNESS,
        },
      });
    }
  }
}
