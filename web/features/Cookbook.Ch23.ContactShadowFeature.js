// 案例 23.9：接触阴影（Contact Shadows）的网页版（对应 Ch23/ContactShadowFeature.cs）。
// 在深度预渲染之后，用一个全屏 Pass 从每个像素出发、沿主光方向在屏幕空间里步进几步，
// 检查有没有被深度缓冲里更靠前的表面挡住，结果写进一张 R8 的全屏纹理 _ContactShadowTexture。
// 接收物体的 Shader 再用屏幕 UV 读它，与阴影贴图的结果取最小值。
//
// 网页引擎没有 URP 那样“声明 ConfigureInput(Depth) 就自动安排 DepthPrepass”的机制，
// 所以这里自己先画一遍 DepthOnly，得到此时的 _CameraDepthTexture。
import { Material } from '../engine/shader.js';
import { RenderPassEvent } from '../engine/features.js';

export default class ContactShadowFeature {
  constructor(engine, data, scene) {
    this.engine = engine; this.scene = scene;
    const s = (data && data.settings) || {};
    this.settings = { length: s.length ?? 0.35, steps: s.steps ?? 16, thickness: s.thickness ?? 0.15, bias: s.bias ?? 0.01, intensity: s.intensity ?? 1 };
  }

  async init() {
    this.material = new Material(await this.engine.shaders.get('Cookbook/Ch23/ContactShadowPass'));
  }

  addPasses(frame, enqueue) {
    const L = frame.mainLight;
    if (!L) return;
    // 方向光的 forward 是光线前进方向，取反得到“指向光源”的 L
    const dir = [-L.forward[0], -L.forward[1], -L.forward[2]];
    // 与 URP 的屏幕空间阴影相同的时机：深度预渲染之后、不透明物体之前
    enqueue(RenderPassEvent.AfterRenderingPrePasses + 1, (fr) => this.execute(fr, dir));
  }

  execute(fr, L) {
    const gl = fr.gl, s = this.settings, W = fr.width, H = fr.height;
    // 1) 深度预渲染（URP 的 DepthPrepass）
    const depthRT = fr.getTemporaryRT('ContactDepthPrepass', W, H, { color: 'R8', depth: 'DEPTH24' });
    this.engine.bindTarget(depthRT);
    gl.depthMask(true); gl.colorMask(true, true, true, true);
    gl.clearColor(1, 1, 1, 1); gl.clearDepth(1);
    gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
    fr.drawRenderers({ queue: 'opaque', lightModes: ['DepthOnly'] });
    fr.setGlobal('_CameraDepthTexture', depthRT.depthTexture);

    // 2) 全屏步进，写 _ContactShadowTexture
    const target = fr.getTemporaryRT('_ContactShadowTexture', W, H, { color: 'R8' });
    this.material.setVector('_ContactParams', [s.length, s.steps, s.thickness, s.bias]);
    this.material.setVector('_ContactLightDir', [L[0], L[1], L[2], s.intensity]);
    fr.blit(null, target, this.material, 0);
    fr.setGlobal('_ContactShadowTexture', target.texture);
    fr.bindCamera();
  }
}
