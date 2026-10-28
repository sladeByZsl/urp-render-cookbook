// 案例 26.10：受击红屏（对应 Ch26/HitFlash.cs）。运行时由 HitFlashTrigger 用 Volume 权重驱动；书中截图用固定 phase。
import { PostFeatureBase, SimplePostPass, defineVolume } from './Cookbook.Ch26.PostFeatureBase.js';

const VOLUME = 'Cookbook.Ch26.HitFlashVolume';
// noiseScale：血丝状边缘的噪声尺度；phase：动画相位
defineVolume(VOLUME, { intensity: 0, color: [0.75, 0.02, 0.02, 1], noiseScale: 6, phase: 0 });

class Pass extends SimplePostPass {
  constructor(m) { super(m, 'Ch26 Hit Flash', VOLUME); }
  isActive(v) { return v.intensity > 0; }
  apply(v) {
    // C# 的 SetColor 写的是 Properties 里没声明的属性，Unity 原样上传（不做 sRGB→线性）
    this.material.setVector('_HitColor', v.color);
    this.material.setVector('_HitParams', [v.intensity, v.noiseScale, v.phase, 0]);   // x 强度, y 噪声尺度, z 相位
  }
}

export default class HitFlashFeature extends PostFeatureBase {
  get shaderName() { return 'Cookbook/Ch26/HitFlash'; }
  createPass(m) { return new Pass(m); }
}
