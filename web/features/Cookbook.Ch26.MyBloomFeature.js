// 案例 26.4：自制 Bloom —— 亮部提取（软阈值）→ 下采样金字塔 → 逐级上采样合并 → 叠加回画面（对应 Ch26/MyBloom.cs）。
import { PostFeatureBase, PostPassBase, defineVolume } from './Cookbook.Ch26.PostFeatureBase.js';

export const BloomDebugView = { None: 0, Prefilter: 1, BloomOnly: 2 };

//#region volume
const VOLUME = 'Cookbook.Ch26.MyBloomVolume';
defineVolume(VOLUME, { threshold: 1, softKnee: 0.5, intensity: 0, scatter: 0.7, tint: [1, 1, 1, 1], maxIterations: 6, debugView: BloomDebugView.None });
//#endregion

class MyBloomPass extends PostPassBase {
  constructor(m) { super(m, 'Ch26 My Bloom'); }

  prepare(frame) {
    const v = frame.getVolume(VOLUME);
    if (!v || !(v.intensity > 0)) return false;
    const m = this.material, threshold = v.threshold;
    // x 阈值, y 膝宽, z scatter, w 强度
    m.setVector('_BloomParams', [threshold, threshold * v.softKnee, v.scatter, v.intensity]);
    // C# 的 SetColor 写的是 Properties 里没声明的属性，Unity 原样上传（不做 sRGB→线性）
    m.setVector('_BloomTint', v.tint);
    this.debug = v.debugView;
    m.setFloat('_BloomDebugView', this.debug);
    this.maxIterations = Math.trunc(v.maxIterations);
    return true;
  }

  render(fr) {
    const PassPrefilter = 0, PassDown = 1, PassUp = 2, PassComposite = 3;
    const m = this.material;
    //#region alloc
    // 金字塔从半分辨率开始，一直缩到短边只剩几个像素或达到最大层数
    let w = Math.max(1, Math.floor(fr.width / 2)), h = Math.max(1, Math.floor(fr.height / 2));
    const levels = Math.min(Math.max(Math.floor(Math.log2(Math.min(w, h))) - 1, 1), this.maxIterations);
    const down = [], up = [];
    for (let i = 0; i < levels; i++) {
      down.push(fr.getTemporaryRT('_Ch26BloomDown' + i, w, h));
      if (i < levels - 1) up.push(fr.getTemporaryRT('_Ch26BloomUp' + i, w, h));
      w = Math.max(1, Math.floor(w / 2)); h = Math.max(1, Math.floor(h / 2));
    }
    const temp = PostPassBase.colorRT(fr, '_Ch26BloomTemp');
    //#endregion

    //#region render
    // 1) 亮部提取 + 第一次降采样（全分辨率 → 1/2）
    fr.blit(fr.cameraColorTexture(), down[0], m, PassPrefilter);
    // 2) 下采样金字塔：1/2 → 1/4 → 1/8 …（13 次采样的抗闪烁下采样核）
    for (let i = 1; i < levels; i++) fr.blit(down[i - 1].texture, down[i], m, PassDown);
    // 3) 上采样：从最小层开始，每级 = lerp(本级下采样结果, 上一级的放大结果, scatter)
    for (let i = levels - 2; i >= 0; i--) {
      const low = i === levels - 2 ? down[i + 1] : up[i + 1];
      fr.blit(down[i].texture, up[i], m, PassUp, { _BloomLowMip: low.texture });
    }
    // 4) 合成：相机颜色 + 泛光 × 强度 × 颜色
    const bloom = this.debug === BloomDebugView.Prefilter ? down[0] : (levels > 1 ? up[0] : down[0]);
    fr.blit(fr.cameraColorTexture(), temp, m, PassComposite, { _BloomTex: bloom.texture });
    fr.blit(temp.texture, 'camera');
    //#endregion
  }
}

export default class MyBloomFeature extends PostFeatureBase {
  get shaderName() { return 'Cookbook/Ch26/MyBloom'; }
  createPass(m) { return new MyBloomPass(m); }
}
