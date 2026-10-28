// 案例 26.3：Kawase 模糊与 Dual Kawase 模糊（对应 Ch26/KawaseBlur.cs）。
import { PostFeatureBase, PostPassBase, defineVolume } from './Cookbook.Ch26.PostFeatureBase.js';

export const KawaseMode = { Kawase: 0, DualKawase: 1 };
const VOLUME = 'Cookbook.Ch26.KawaseBlurVolume';
// iterations：Kawase 为迭代次数，Dual Kawase 为金字塔层数；offset：采样偏移倍数
defineVolume(VOLUME, { mode: KawaseMode.DualKawase, iterations: 0, offset: 1 });

class KawaseBlurPass extends PostPassBase {
  constructor(m) { super(m, 'Ch26 Kawase Blur'); }

  prepare(frame) {
    const v = frame.getVolume(VOLUME);
    if (!v || !(Math.trunc(v.iterations) > 0)) return false;
    this.mode = v.mode;
    this.iterations = Math.min(8, Math.trunc(v.iterations));
    this.offset = v.offset;
    return true;
  }

  render(fr) {
    if (this.mode === KawaseMode.Kawase) this.renderKawase(fr);
    else this.renderDualKawase(fr);
  }

  //#region kawase
  renderKawase(fr) {
    const PassKawase = 0;
    let src = PostPassBase.colorRT(fr, '_Ch26KawaseA', 2), dst = PostPassBase.colorRT(fr, '_Ch26KawaseB', 2);
    fr.blit(fr.cameraColorTexture(), src);
    for (let i = 0; i < this.iterations; i++) {
      // 每次迭代偏移不同（C# 用 cmd.SetGlobalFloat 记录进命令缓冲；这里是立即执行，直接逐次传入）
      fr.blit(src.texture, dst, this.material, PassKawase, { _KawaseOffset: (i + 0.5) * this.offset });
      [src, dst] = [dst, src];
    }
    fr.blit(src.texture, 'camera');
  }
  //#endregion

  //#region dual
  renderDualKawase(fr) {
    const PassDown = 1, PassUp = 2;
    const u = { _KawaseOffset: this.offset };
    // 第 i 层是 1/2^i 分辨率；第 0 层就是相机颜色本身，不分配
    const pyramid = [null];
    for (let i = 1; i <= this.iterations; i++) pyramid.push(PostPassBase.colorRT(fr, '_Ch26DualKawase' + i, 1 << i));
    // 下行：全分辨率 → 1/2 → 1/4 …，每一步用 5 次采样的 Down 核
    let prev = fr.cameraColorTexture();
    for (let i = 1; i <= this.iterations; i++) {
      fr.blit(prev, pyramid[i], this.material, PassDown, u);
      prev = pyramid[i].texture;
    }
    // 上行：逐级放大回去，每一步用 8 次采样的 Up 核，最后一步直接写回相机颜色
    for (let i = this.iterations - 1; i >= 0; i--) {
      fr.blit(pyramid[i + 1].texture, i === 0 ? 'camera' : pyramid[i], this.material, PassUp, u);
    }
  }
  //#endregion
}

export default class KawaseBlurFeature extends PostFeatureBase {
  get shaderName() { return 'Cookbook/Ch26/KawaseBlur'; }
  createPass(m) { return new KawaseBlurPass(m); }
}
