// 案例 26.7：像素化 + 调色板量化 + 有序抖动（对应 Ch26/Pixelate.cs）。
import { PostFeatureBase, SimplePostPass, defineVolume } from './Cookbook.Ch26.PostFeatureBase.js';

const VOLUME = 'Cookbook.Ch26.PixelateVolume';
// pixelSize：一个“大像素”占多少屏幕像素（1 = 关闭）；colorLevels：每通道几级颜色（0 = 不量化）；dither：Bayer 抖动强度
defineVolume(VOLUME, { pixelSize: 1, colorLevels: 0, dither: 1 });

class Pass extends SimplePostPass {
  constructor(m) { super(m, 'Ch26 Pixelate', VOLUME); }
  isActive(v) { return Math.trunc(v.pixelSize) > 1 || Math.trunc(v.colorLevels) > 0; }
  apply(v) { this.material.setVector('_PixelateParams', [Math.trunc(v.pixelSize), Math.trunc(v.colorLevels), v.dither, 0]); }
}

export default class PixelateFeature extends PostFeatureBase {
  get shaderName() { return 'Cookbook/Ch26/Pixelate'; }
  createPass(m) { return new Pass(m); }
}
