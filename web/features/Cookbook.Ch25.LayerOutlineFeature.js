// 案例 25.5 / 25.6：只给某个 Layer 的物体画遮罩，再根据遮罩画描边（对应 Ch25/LayerOutlineFeature.cs）。
// 两个 Pass：MaskPass 用 DrawRenderers 把选中层画进一张 R8 遮罩；CompositePass 读遮罩、膨胀、叠到屏幕上。
import { Material } from '../engine/shader.js';
import { RenderPassEvent, layerMask } from '../engine/features.js';

// 只画原材质里有这些 LightMode 的物体（URP 前向渲染用到的三个标签）
const SHADER_TAGS = ['UniversalForward', 'UniversalForwardOnly', 'SRPDefaultUnlit'];

export default class LayerOutlineFeature {
  constructor(engine, data, scene) {
    this.engine = engine;
    this.data = data || {};
    this.settings = {
      layerMask: 1 << 8, seeThrough: true, outlineColor: [1, 0.55, 0.1, 1], fillColor: [1, 0.55, 0.1, 0],
      width: 4, mode: 0, passEvent: RenderPassEvent.AfterRenderingTransparents, ...(this.data.settings || {}),
    };
  }

  async init() {
    const sh = (ref, def) => this.engine.shaders.get((ref && ref.shader) || def);
    this.maskMaterial = new Material(await sh(this.data.maskShader, 'Cookbook/Ch25/LayerMaskSolid'));
    this.outlineMaterial = new Material(await sh(this.data.outlineShader, 'Cookbook/Ch25/LayerOutline'));
  }

  addPasses(frame, enqueue) {
    const s = this.settings;
    // CompositePass.Setup
    // 注意：C# 的 material.SetColor 写的是 Properties 块里没声明的属性，Unity 原样上传、不做 sRGB→线性（和书中图实测一致），所以用 setVector
    this.outlineMaterial.setVector('_OutlineColor', s.outlineColor);
    this.outlineMaterial.setVector('_FillColor', s.fillColor);
    this.outlineMaterial.setFloat('_OutlineWidth', s.width);
    const shaderPass = s.mode === 0 ? 0 : 1;
    // 两个 Pass 同一个事件：入队顺序就是执行顺序
    enqueue(s.passEvent, (fr) => this.maskPass(fr), 'Ch25 Layer Mask');
    enqueue(s.passEvent, (fr) => {
      // 画回相机颜色：在相机目标上画一个全屏三角形，靠混合叠加上去
      fr.blit(this.mask, 'camera', this.outlineMaterial, shaderPass);
    }, 'Ch25 Outline Composite');
  }

  //#region mask-pass
  maskPass(fr) {
    const E = fr.engine, gl = fr.gl, s = this.settings;
    // 遮罩与相机同尺寸、同 MSAA（要和相机深度一起绑定，两者采样数必须一致），单通道 8 位即可
    const rt = E.rt('ch25:_Ch25LayerMask', fr.width, fr.height, { color: 'R8', depth: null, samples: fr.msaa, renderbuffers: true });
    // ConfigureTarget(mask, cameraDepth)：把相机的深度缓冲挂到遮罩的 FBO 上（借用，不清除）
    gl.bindFramebuffer(gl.FRAMEBUFFER, rt.fbo);
    gl.framebufferRenderbuffer(gl.FRAMEBUFFER, gl.DEPTH_STENCIL_ATTACHMENT, gl.RENDERBUFFER, fr.cameraTarget.depthRB);
    E.bindTarget(rt);
    // ConfigureClear(ClearFlag.Color, Color.clear)：只清颜色，深度绝不能清
    gl.colorMask(true, true, true, true);
    gl.clearColor(0, 0, 0, 0);
    gl.clear(gl.COLOR_BUFFER_BIT);
    // RenderStateBlock 覆盖深度状态：透视模式 ZTest Always，否则 LEqual；不写深度
    const pass = this.maskMaterial.shader.passes[0];
    fr.drawRenderers({
      queue: 'all', lightModes: SHADER_TAGS, layerMask: layerMask(s.layerMask),
      overrideMaterial: this.maskMaterial, overridePass: 0,
      state: { ...pass.state, zwrite: 'Off', ztest: s.seeThrough ? 'Always' : 'LEqual' },
    });
    E.glc.resolve(rt, { color: true });
    this.mask = rt.texture;
  }
  //#endregion
}
