// 案例 26.9：基于深度 + 法线的 Sobel 描边（屏幕空间描边）（对应 Ch26/EdgeDetect.cs）。
import { PostFeatureBase, SimplePostPass, PassInput, defineVolume, renderDepthNormals } from './Cookbook.Ch26.PostFeatureBase.js';

//#region volume
const VOLUME = 'Cookbook.Ch26.EdgeDetectVolume';
// thickness：采样间距（像素）；depthThreshold：深度梯度 / 中心深度 超过它算边；normalThreshold：设到最大即“只用深度”
// edgesOnly：0 = 线叠在原图上，1 = 只显示线（背景换成 backgroundColor）
defineVolume(VOLUME, {
  intensity: 0, thickness: 1, depthThreshold: 0.15, normalThreshold: 1.5,
  edgeColor: [0.05, 0.05, 0.08, 1], edgesOnly: 0, backgroundColor: [0.95, 0.93, 0.88, 1],
});
//#endregion

//#region pass
class Pass extends SimplePostPass {
  constructor(m) { super(m, 'Ch26 Edge Detect', VOLUME); }

  // 本 Pass 需要 _CameraDepthTexture 和 _CameraNormalsTexture。
  // Normal 会让 URP 额外跑一遍 DepthNormals 预渲染（前向路径下），这是这个效果的主要开销。
  get requiredInputs() { return PassInput.Depth | PassInput.Normal; }
  renderNormals(fr) { this.prepass = renderDepthNormals(fr); }
  render(fr) {
    // 前向路径 + Normal 输入时，URP 的 _CameraDepthTexture 来自 DepthNormals 预渲染（无 MSAA）
    if (this.prepass) fr.setGlobal('_CameraDepthTexture', this.prepass.depthTexture);
    super.render(fr);
  }

  isActive(v) { return v.intensity > 0; }
  apply(v) {
    const m = this.material;
    m.setVector('_EdgeParams', [v.intensity, v.thickness, v.depthThreshold, v.normalThreshold]);   // x 强度, y 粗细, z 深度阈值, w 法线阈值
    // C# 的 SetColor 写的是 Properties 里没声明的属性，Unity 原样上传（不做 sRGB→线性）
    m.setVector('_EdgeColor', v.edgeColor);
    const bg = v.backgroundColor;
    m.setVector('_EdgeBgColor', [bg[0], bg[1], bg[2], v.edgesOnly]);   // a = edgesOnly
  }
}
//#endregion

export default class EdgeDetectFeature extends PostFeatureBase {
  get shaderName() { return 'Cookbook/Ch26/EdgeDetect'; }
  createPass(m) { return new Pass(m); }
}
