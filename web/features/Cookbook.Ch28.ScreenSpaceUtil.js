// 第 28 章几个 Feature 共用：ScriptableRenderPassInput 位定义 + DepthNormals 预渲染。
// （不是 Renderer Feature，只是被 Cookbook.Ch28.*Feature.js 导入的工具模块）
export const PassInput = { None: 0, Depth: 1, Normal: 2, Color: 4, Motion: 8 };

// 前向路径下请求 Normal 时，URP 在不透明物体之前多跑一遍 DepthNormals 预渲染：
// 得到 _CameraNormalsTexture（世界空间法线），并且 _CameraDepthTexture 也取自这次预渲染（无 MSAA）。
export function renderDepthNormals(fr) {
  const gl = fr.gl;
  const rt = fr.getTemporaryRT('_Ch28DepthNormals', fr.width, fr.height, { color: 'RGBA16F', depth: 'DEPTH24' });
  fr.engine.bindTarget(rt);
  gl.colorMask(true, true, true, true); gl.depthMask(true);
  gl.clearColor(0, 0, 0, 0); gl.clearDepth(1);
  gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
  fr.drawRenderers({ queue: 'opaque', lightModes: ['DepthNormals', 'DepthNormalsOnly'], layerMask: fr.scene.rendererData.m_OpaqueLayerMask ?? -1 });
  fr.setGlobal('_CameraNormalsTexture', rt.texture);
  fr.setGlobal('_CameraDepthTexture', rt.depthTexture);
  fr.bindCamera();
  return rt;
}

// 相机深度：没有预渲染时，从相机目标解析一份
export function ensureDepth(fr) {
  fr.setGlobal('_CameraDepthTexture', fr.cameraDepthTexture());
}
