// 案例 26.2：可分离高斯模糊 + 降采样 + 乒乓 RT（对应 Ch26/GaussianBlur.cs）。
import { PostFeatureBase, PostPassBase, defineVolume } from './Cookbook.Ch26.PostFeatureBase.js';

const VOLUME = 'Cookbook.Ch26.GaussianBlurVolume';
// spread：采样间距（以低分辨率纹素为单位，0 = 关闭）；iterations：水平+竖直 算一次迭代；downsample：先缩小到 1/N
defineVolume(VOLUME, { spread: 0, iterations: 2, downsample: 2 });

//#region pass
class GaussianBlurPass extends PostPassBase {
  constructor(m) { super(m, 'Ch26 Gaussian Blur'); }

  prepare(frame) {
    const v = frame.getVolume(VOLUME);
    if (!v || !(v.spread > 0)) return false;
    this.material.setFloat('_Spread', v.spread);
    this.iterations = Math.trunc(v.iterations);
    this.downsample = Math.max(1, Math.trunc(v.downsample));
    return true;
  }

  render(fr) {
    const PassH = 0, PassV = 1;
    // 两张低分辨率 RT，来回倒（乒乓）
    const A = PostPassBase.colorRT(fr, '_Ch26BlurA', this.downsample);
    const B = PostPassBase.colorRT(fr, '_Ch26BlurB', this.downsample);
    // 1) 降采样：双线性拷贝到小图，本身就相当于一次 2×2 盒式滤波
    fr.blit(fr.cameraColorTexture(), A);
    // 2) 迭代：A →(水平)→ B →(竖直)→ A
    for (let i = 0; i < this.iterations; i++) {
      fr.blit(A.texture, B, this.material, PassH);
      fr.blit(B.texture, A, this.material, PassV);
    }
    // 3) 放大回全分辨率（双线性），覆盖相机颜色
    fr.blit(A.texture, 'camera');
  }
}
//#endregion

export default class GaussianBlurFeature extends PostFeatureBase {
  get shaderName() { return 'Cookbook/Ch26/GaussianBlur'; }
  createPass(m) { return new GaussianBlurPass(m); }
}
