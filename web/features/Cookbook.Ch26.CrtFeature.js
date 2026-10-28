// 案例 26.8：CRT 显示器——屏幕弯曲、扫描线、荧光粉栅格、边缘暗角、轻微色差与闪烁（对应 Ch26/Crt.cs）。
import { PostFeatureBase, SimplePostPass, defineVolume } from './Cookbook.Ch26.PostFeatureBase.js';

const VOLUME = 'Cookbook.Ch26.CrtVolume';
// intensity：总开关强度（0 = 关闭）；lineCount：模拟的扫描线行数；maskStrength：RGB 荧光粉栅格强度
defineVolume(VOLUME, { intensity: 0, curvature: 0.12, lineCount: 240, scanlineStrength: 0.5, maskStrength: 0.35, flicker: 0.03 });

class Pass extends SimplePostPass {
  constructor(m) { super(m, 'Ch26 CRT', VOLUME); }
  isActive(v) { return v.intensity > 0; }
  apply(v) {
    this.material.setVector('_CrtParams0', [v.intensity, v.curvature, v.lineCount, v.scanlineStrength]);   // x 强度, y 弯曲, z 行数, w 扫描线强度
    this.material.setVector('_CrtParams1', [v.maskStrength, v.flicker, 0, 0]);                           // x 栅格强度, y 闪烁
  }
}

export default class CrtFeature extends PostFeatureBase {
  get shaderName() { return 'Cookbook/Ch26/Crt'; }
  createPass(m) { return new Pass(m); }
}
