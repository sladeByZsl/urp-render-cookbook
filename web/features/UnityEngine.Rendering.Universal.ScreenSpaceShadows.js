// URP 自带的 ScreenSpaceShadows Renderer Feature（网页版，对应 Runtime/RendererFeatures/ScreenSpaceShadows.cs）。
// 1) 不透明物体之前：深度预渲染 → 全屏 Pass 把主光阴影解析进 _ScreenSpaceShadowmapTexture，并打开 _MAIN_LIGHT_SHADOWS_SCREEN
//    （GLSL 版里是 uniform _MainLightShadowsScreen），不透明物体按屏幕坐标读这张图；
// 2) 不透明物体之后（ScreenSpaceShadowsPostPass）：关掉它，半透明物体仍然直接采样阴影图。
// 网页引擎没有 URP 那样按需安排的 DepthPrepass，这里自己画一遍 DepthOnly。
import { Material } from '../engine/shader.js';
import { RenderPassEvent } from '../engine/features.js';

export default class ScreenSpaceShadows {
  constructor(engine, data, scene) {
    this.engine = engine; this.scene = scene;
    this.shaderName = (data && data.m_Shader && data.m_Shader.shader) || 'Hidden/Universal Render Pipeline/ScreenSpaceShadows';
  }

  async init() {
    this.material = new Material(await this.engine.shaders.get(this.shaderName));
  }

  addPasses(frame, enqueue) {
    if (!frame.mainLight) return;
    enqueue(RenderPassEvent.AfterRenderingPrePasses, (fr) => this.resolve(fr));
    enqueue(RenderPassEvent.AfterRenderingOpaques, (fr) => fr.setGlobal('_MainLightShadowsScreen', 0));
  }

  resolve(fr) {
    const gl = fr.gl, W = fr.width, H = fr.height;
    const depthRT = fr.getTemporaryRT('SSShadowsDepthPrepass', W, H, { color: 'R8', depth: 'DEPTH24' });
    this.engine.bindTarget(depthRT);
    gl.depthMask(true); gl.colorMask(true, true, true, true);
    gl.clearColor(1, 1, 1, 1); gl.clearDepth(1);
    gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
    fr.drawRenderers({ queue: 'opaque', lightModes: ['DepthOnly'] });
    fr.setGlobal('_CameraDepthTexture', depthRT.depthTexture);

    const target = fr.getTemporaryRT('_ScreenSpaceShadowmapTexture', W, H, { color: 'R8' });
    fr.blit(null, target, this.material, 0, { _MainLightShadowsScreen: 0 });
    fr.setGlobal('_ScreenSpaceShadowmapTexture', target.texture);
    fr.setGlobal('_MainLightShadowsScreen', 1);
    fr.bindCamera();
  }
}
