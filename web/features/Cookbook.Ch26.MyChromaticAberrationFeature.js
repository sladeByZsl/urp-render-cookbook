// 案例 26.6：色差（对应 Ch26/LensEffects.cs 里的 MyChromaticAberration + MyChromaticAberrationFeature）。
import { PostFeatureBase, SimplePostPass, defineVolume } from './Cookbook.Ch26.PostFeatureBase.js';

const VOLUME = 'Cookbook.Ch26.MyChromaticAberration';
// samples：沿径向分几段采样；3 = 只取 RGB 三次，越多色散越平滑
defineVolume(VOLUME, { intensity: 0, samples: 6 });

class Pass extends SimplePostPass {
  constructor(m) { super(m, 'Ch26 Chromatic Aberration', VOLUME); }
  isActive(v) { return v.intensity > 0; }
  apply(v) { this.material.setVector('_CAParams', [v.intensity, Math.trunc(v.samples), 0, 0]); }
}

export default class MyChromaticAberrationFeature extends PostFeatureBase {
  get shaderName() { return 'Cookbook/Ch26/MyChromaticAberration'; }
  createPass(m) { return new Pass(m); }
}
