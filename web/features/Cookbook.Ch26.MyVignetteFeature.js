// 案例 26.6：暗角（对应 Ch26/LensEffects.cs 里的 MyVignette + MyVignetteFeature）。
import { PostFeatureBase, SimplePostPass, defineVolume } from './Cookbook.Ch26.PostFeatureBase.js';

const VOLUME = 'Cookbook.Ch26.MyVignette';
// rounded：勾选后按屏幕宽高比修正成正圆
defineVolume(VOLUME, { color: [0, 0, 0, 1], center: [0.5, 0.5], intensity: 0, smoothness: 0.5, rounded: false });

class Pass extends SimplePostPass {
  constructor(m) { super(m, 'Ch26 Vignette', VOLUME); }
  isActive(v) { return v.intensity > 0; }
  apply(v) {
    // C# 的 SetColor 写的是 Properties 里没声明的属性，Unity 原样上传（不做 sRGB→线性）
    this.material.setVector('_VignetteColor', v.color);
    const c = v.center;
    this.material.setVector('_VignetteParams', [c[0], c[1], v.intensity, v.smoothness]);   // xy 中心, z 强度, w 柔和度
    this.material.setFloat('_VignetteRounded', v.rounded ? 1 : 0);
  }
}

export default class MyVignetteFeature extends PostFeatureBase {
  get shaderName() { return 'Cookbook/Ch26/MyVignette'; }
  createPass(m) { return new Pass(m); }
}
