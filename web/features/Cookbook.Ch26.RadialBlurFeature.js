// 案例 26.5：径向模糊（冲刺/爆炸冲击感）（对应 Ch26/RadialBlur.cs）。
import { PostFeatureBase, SimplePostPass, defineVolume } from './Cookbook.Ch26.PostFeatureBase.js';

//#region volume
const VOLUME = 'Cookbook.Ch26.RadialBlurVolume';
// strength：每个像素向中心方向最多拖拽的比例；clearRadius：中心这一圈半径内保持清晰（屏幕高度为 1）
defineVolume(VOLUME, { center: [0.5, 0.5], strength: 0, samples: 12, clearRadius: 0.1 });
//#endregion

//#region pass
class RadialBlurPass extends SimplePostPass {
  constructor(m) { super(m, 'Ch26 Radial Blur', VOLUME); }
  isActive(v) { return v.strength > 0; }
  apply(v) {
    const c = v.center;
    this.material.setVector('_RadialParams', [c[0], c[1], v.strength, Math.trunc(v.samples)]);   // xy 中心, z 强度, w 采样数
    this.material.setFloat('_ClearRadius', v.clearRadius);
  }
}
//#endregion

export default class RadialBlurFeature extends PostFeatureBase {
  get shaderName() { return 'Cookbook/Ch26/RadialBlur'; }
  createPass(m) { return new RadialBlurPass(m); }
}
