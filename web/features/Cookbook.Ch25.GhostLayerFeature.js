// 案例 25.7：把某个 Layer 单独渲染到离屏 RT（颜色+自己的深度），再整体半透明合成回屏幕（对应 Ch25/GhostLayerFeature.cs）。
// 用法：把该 Layer 从 Renderer 的 Opaque Layer Mask 里去掉（否则它会在主 Pass 里再画一次）。
import { Material } from '../engine/shader.js';
import { RenderPassEvent, layerMask } from '../engine/features.js';

const SHADER_TAGS = ['UniversalForward', 'UniversalForwardOnly', 'SRPDefaultUnlit'];

export default class GhostLayerFeature {
  constructor(engine, data, scene) {
    this.engine = engine;
    this.data = data || {};
    this.settings = { layerMask: 1 << 9, opacity: 0.45, tint: [0.75, 0.95, 1.1, 1], rimColor: [0.3, 1.2, 2.0, 1], rimWidth: 3, ...(this.data.settings || {}) };
  }

  async init() {
    const name = (this.data.compositeShader && this.data.compositeShader.shader) || 'Cookbook/Ch25/GhostComposite';
    this.material = new Material(await this.engine.shaders.get(name));
  }

  addPasses(frame, enqueue) {
    const s = this.settings, m = this.material;
    // CompositePass.Setup
    m.setFloat('_Opacity', s.opacity);
    // 注意：C# 的 material.SetColor 写的是 Properties 块里没声明的属性，Unity 原样上传、不做 sRGB→线性（和书中图实测一致），所以用 setVector
    m.setVector('_Tint', s.tint);
    m.setVector('_RimColor', s.rimColor);
    m.setFloat('_RimWidth', s.rimWidth);
    // 合成时要和场景深度比较 → 需要 _CameraDepthTexture
    frame.requireDepth = true;
    enqueue(RenderPassEvent.AfterRenderingOpaques, (fr) => this.layerPass(fr), 'Ch25 Ghost Layer');
    enqueue(RenderPassEvent.AfterRenderingTransparents, (fr) => {
      fr.blit(this.layer.texture, 'camera', m, 0, { _GhostDepth: this.layer.depthTexture });
    }, 'Ch25 Ghost Composite');
  }

  //#region layer-pass
  layerPass(fr) {
    const gl = fr.gl;
    // 颜色：带 Alpha 的半精度浮点（HDR 光照结果 + 覆盖率）；深度：之后还要在合成 Shader 里当纹理采样
    const rt = fr.getTemporaryRT('_Ch25GhostColor', fr.width, fr.height, { color: 'RGBA16F', depth: 'DEPTH24' });
    fr.engine.bindTarget(rt);
    // ConfigureClear(ClearFlag.All, Color.clear)：颜色清成全透明，深度清成最远
    gl.colorMask(true, true, true, true); gl.depthMask(true);
    gl.clearColor(0, 0, 0, 0); gl.clearDepth(1);
    gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
    // 不覆盖材质：用物体自己的 Lit 材质正常打光，只是画到了另一张 RT 上
    fr.drawRenderers({ queue: 'opaque', lightModes: SHADER_TAGS, layerMask: layerMask(this.settings.layerMask) });
    this.layer = rt;
    fr.bindCamera();
  }
  //#endregion
}
