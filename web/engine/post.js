// 后处理：Volume 混合 + URP 内置效果（Bloom、Tonemapping、颜色分级、Vignette、镜头畸变、色差、胶片颗粒…）
// 算法照 URP 14 的 PostProcessPass / ColorGradingLutPass / UberPost 写：
//   颜色分级和 URP 一样先烘焙进一张 LUT（LutBuilderHdr/Ldr），Uber 里查表。
// 景深、运动模糊、Panini 以模块形式注册到 POST_EFFECTS（见 post/extra.js）。
import { Material } from './shader.js';
import { srgbToLinear } from './math.js';

const NS = 'UnityEngine.Rendering.Universal.';

// TextureCurve 的序列化形式（与导出数据一致）
const curve = (keys, zero, loop) => ({ '<length>k__BackingField': keys.length, m_Loop: loop, m_ZeroValue: zero, m_Range: 1, m_Curve: keys });
const LINEAR_CURVE = () => curve([[0, 0, 1, 1], [1, 1, 1, 1]], 0, false);

// 每个 Volume 组件参数的默认值（URP 14，Runtime/Overrides/*.cs）
export const VOLUME_DEFAULTS = {
  [NS + 'Bloom']: { threshold: 0.9, intensity: 0, scatter: 0.7, clamp: 65472, tint: [1, 1, 1, 1], highQualityFiltering: false, downscale: 0, maxIterations: 6, dirtTexture: null, dirtIntensity: 0 },
  [NS + 'Tonemapping']: { mode: 0 },
  [NS + 'ColorAdjustments']: { postExposure: 0, contrast: 0, colorFilter: [1, 1, 1, 1], hueShift: 0, saturation: 0 },
  [NS + 'Vignette']: { color: [0, 0, 0, 1], center: [0.5, 0.5], intensity: 0, smoothness: 0.2, rounded: false },
  [NS + 'WhiteBalance']: { temperature: 0, tint: 0 },
  [NS + 'LiftGammaGain']: { lift: [1, 1, 1, 0], gamma: [1, 1, 1, 0], gain: [1, 1, 1, 0] },
  [NS + 'ShadowsMidtonesHighlights']: { shadows: [1, 1, 1, 0], midtones: [1, 1, 1, 0], highlights: [1, 1, 1, 0], shadowsStart: 0, shadowsEnd: 0.3, highlightsStart: 0.55, highlightsEnd: 1 },
  [NS + 'SplitToning']: { shadows: [0.5, 0.5, 0.5, 1], highlights: [0.5, 0.5, 0.5, 1], balance: 0 },
  [NS + 'ChannelMixer']: { redOutRedIn: 100, redOutGreenIn: 0, redOutBlueIn: 0, greenOutRedIn: 0, greenOutGreenIn: 100, greenOutBlueIn: 0, blueOutRedIn: 0, blueOutGreenIn: 0, blueOutBlueIn: 100 },
  [NS + 'ColorCurves']: {
    master: LINEAR_CURVE(), red: LINEAR_CURVE(), green: LINEAR_CURVE(), blue: LINEAR_CURVE(),
    hueVsHue: curve([], 0.5, true), hueVsSat: curve([], 0.5, true), satVsSat: curve([], 0.5, false), lumVsSat: curve([], 0.5, false),
  },
  [NS + 'ColorLookup']: { texture: null, contribution: 0 },
  [NS + 'ChromaticAberration']: { intensity: 0 },
  [NS + 'FilmGrain']: { type: 0, intensity: 0, response: 0.8, texture: null },
  [NS + 'LensDistortion']: { intensity: 0, xMultiplier: 1, yMultiplier: 1, center: [0.5, 0.5], scale: 1 },
  [NS + 'DepthOfField']: { mode: 0, gaussianStart: 10, gaussianEnd: 30, gaussianMaxRadius: 1, highQualitySampling: false, focusDistance: 10, aperture: 5.6, focalLength: 50, bladeCount: 5, bladeCurvature: 1, bladeRotation: 0 },
  [NS + 'MotionBlur']: { mode: 0, quality: 0, intensity: 0, clamp: 0.05 },
  [NS + 'PaniniProjection']: { distance: 0, cropToFit: 1 },
};

// URP 的 PostProcessData 里的胶片颗粒贴图（FilmGrainLookup 枚举顺序），拷贝在 data/textures/ 下
export const FILM_GRAIN_TEXTURES = ['Thin01', 'Thin02', 'Medium01', 'Medium02', 'Medium03', 'Medium04', 'Medium05', 'Medium06', 'Large01', 'Large02'].map((n) => `urp_FilmGrain_${n}.png`);

// 枚举参数不插值（VolumeParameter<T>.Interp：t > 0 取新值），整数参数插值后取整
const ENUM_PARAMS = new Set(['mode', 'quality', 'type', 'downscale', 'neutralHDRRangeReductionMode', 'acesPreset']);
const INT_PARAMS = new Set(['maxIterations', 'bladeCount', 'skipIterations']);

// 其它模块可以往这里注册：{ order, render(post, frame, src, vol) → 新的 src 贴图 }，order < 100 在 Bloom 之前
export const POST_EFFECTS = [];

export class PostProcess {
  constructor(engine) { this.engine = engine; this.textures = new Map(); }

  async init() {
    const E = this.engine;
    this.shader = await E.shaders.get('Hidden/Cookbook/PostFX');
    this.mat = new Material(this.shader);
    const extra = await import('./post/extra.js');
    if (extra.init) await extra.init(E);
    // Volume 里引用的贴图（LUT、镜头脏污、颗粒）要在渲染前加载好：场景加载完成后顺带预加载
    const load = E.loadScene.bind(E);
    E.loadScene = async (...args) => { const scene = await load(...args); await this.prepare(scene); return scene; };
  }

  async prepare(scene) {
    const keys = new Set();
    for (const v of scene.volumes) for (const c of v.components) for (const p of Object.values(c.data || {})) {
      const t = p && p.m_Value && p.m_Value.texture;
      if (t) keys.add(t);
    }
    const vol = this.resolveVolumes(scene);
    const fg = vol[NS + 'FilmGrain'];
    if (fg) keys.add(FILM_GRAIN_TEXTURES[fg.type] || FILM_GRAIN_TEXTURES[0]);
    await Promise.all([...keys].map(async (k) => {
      if (this.textures.has(k)) return;
      try { this.textures.set(k, await this.engine.assets.texture(k)); } catch (e) { console.warn(e.message); }
    }));
  }

  // Volume 里的贴图参数（{texture: key}）→ GL 贴图；还没加载时返回 null
  tex(v) {
    if (!v) return null;
    const k = typeof v === 'string' ? v : v.texture;
    const t = k && this.textures.get(k);
    if (!t && k && !this.textures.has(k)) {
      this.textures.set(k, null);
      this.engine.assets.texture(k).then((x) => this.textures.set(k, x)).catch((e) => console.warn(e.message));
    }
    return t || null;
  }

  // 按优先级混合所有全局 Volume，返回 { 类型全名: {参数: 值} }（VolumeManager.OverrideData + 各参数的 Interp）
  resolveVolumes(scene) {
    const out = {};
    const vols = scene.volumes.filter((v) => v.obj.active && v.enabled !== false && v.isGlobal).sort((a, b) => a.priority - b.priority);
    for (const v of vols) {
      const w = Math.min(1, Math.max(0, v.weight ?? 1));
      for (const c of v.components) {
        if (!c.active) continue;
        const dst = out[c.type] || (out[c.type] = { ...structuredClone(VOLUME_DEFAULTS[c.type] || {}), _active: true });
        for (const [k, p] of Object.entries(c.data)) {
          if (!p || typeof p !== 'object' || !('m_OverrideState' in p)) continue;
          if (!p.m_OverrideState) continue;
          const val = p.m_Value, from = dst[k];
          if (from === undefined || w >= 1) dst[k] = val;   // 自定义组件没有默认值：直接取值（与原行为一致）
          else if (typeof val === 'number' && typeof from === 'number') {
            if (ENUM_PARAMS.has(k)) { if (w > 0) dst[k] = val; }
            else { const x = from + (val - from) * w; dst[k] = INT_PARAMS.has(k) ? Math.trunc(x) : x; }
          } else if (Array.isArray(val) && Array.isArray(from) && val.length === from.length && val.every((x) => typeof x === 'number')) {
            dst[k] = from.map((f, i) => f + (val[i] - f) * w);
          } else if (w > 0) dst[k] = val;
        }
      }
    }
    return out;
  }

  render(frame) {
    const E = this.engine;
    const vol = this.resolveVolumes(frame.scene);
    frame.volume = vol;
    const get = (t) => vol[NS + t] || VOLUME_DEFAULTS[NS + t];
    let src = frame.cameraColorTexture();
    const W = frame.width, H = frame.height;

    for (const fx of POST_EFFECTS.filter((f) => f.order < 100).sort((a, b) => a.order - b.order)) src = fx.render(this, frame, src, vol) || src;

    // ---- Bloom ----
    const bloom = get('Bloom');
    let bloomTex = null;
    if (bloom.intensity > 0) bloomTex = this.bloom(frame, src, bloom, W, H);

    for (const fx of POST_EFFECTS.filter((f) => f.order >= 100 && f.order < 200).sort((a, b) => a.order - b.order)) src = fx.render(this, frame, src, vol) || src;

    // ---- 颜色分级 LUT（ColorGradingLutPass）----
    const a = frame.scene.asset || {};
    const hdrGrading = a.m_SupportsHDR !== false && a.m_ColorGradingMode === 1;
    const lutSize = a.m_ColorGradingLutSize || 32;
    const lut = this.buildLut(frame, vol, hdrGrading, lutSize);

    // ---- Uber：镜头畸变 + 色差 + Bloom 合成 + 暗角 + 查 LUT + 胶片颗粒 ----
    const ca = get('ColorAdjustments'), vg = get('Vignette');
    const ld = get('LensDistortion'), chroma = get('ChromaticAberration'), cl = get('ColorLookup'), fg = get('FilmGrain');
    const u = {
      _PostExposure: Math.pow(2, ca.postExposure),
      _HDRGrading: hdrGrading ? 1 : 0,
      _InternalLut: lut,
      _Lut_Params: [1 / (lutSize * lutSize), 1 / lutSize, lutSize - 1, 0],
      _TonemapMode: get('Tonemapping').mode,
      _Vignette1: [vg.color[0], vg.color[1], vg.color[2], vg.rounded ? W / H : 1],
      _Vignette2: [vg.center[0], vg.center[1], vg.intensity * 3, vg.smoothness * 5],
      _BloomEnabled: 0, _LensDirt_Intensity: 0, _DistortionEnabled: 0, _Chroma_Params: 0, _GrainEnabled: 0,
      _UserLut_Params: [0, 0, 0, 0],
    };
    if (bloomTex) {
      let tint = lin(bloom.tint);
      const luma = 0.2126729 * tint[0] + 0.7151522 * tint[1] + 0.072175 * tint[2];
      tint = luma > 0 ? tint.map((x) => x / luma) : [1, 1, 1];
      u._Bloom_Texture = bloomTex;
      u._Bloom_TexSize = [bloomTex.width, bloomTex.height, 1 / bloomTex.width, 1 / bloomTex.height];
      u._BloomParams = [bloom.intensity, tint[0], tint[1], tint[2]];
      u._BloomEnabled = bloom.highQualityFiltering ? 2 : 1;
      // 镜头脏污：按 cover 方式铺满屏幕
      const dirt = this.tex(bloom.dirtTexture) || E.glc.defaults.black;
      const dirtRatio = dirt.width / dirt.height, screenRatio = W / H;
      const so = [1, 1, 0, 0];
      if (dirtRatio > screenRatio) { so[0] = screenRatio / dirtRatio; so[2] = (1 - so[0]) * 0.5; }
      else if (screenRatio > dirtRatio) { so[1] = dirtRatio / screenRatio; so[3] = (1 - so[1]) * 0.5; }
      u._LensDirt_Texture = dirt; u._LensDirt_Params = so; u._LensDirt_Intensity = bloom.dirtIntensity;
    }
    // Lens Distortion（SetupLensDistortion）
    if (Math.abs(ld.intensity) > 0 && (ld.xMultiplier > 0 || ld.yMultiplier > 0)) {
      const amount = 1.6 * Math.max(Math.abs(ld.intensity * 100), 1);
      const theta = (Math.PI / 180) * Math.min(160, amount);
      const sigma = 2 * Math.tan(theta * 0.5);
      u._Distortion_Params1 = [ld.center[0] * 2 - 1, ld.center[1] * 2 - 1, Math.max(ld.xMultiplier, 1e-4), Math.max(ld.yMultiplier, 1e-4)];
      u._Distortion_Params2 = [ld.intensity >= 0 ? theta : 1 / theta, sigma, 1 / ld.scale, ld.intensity * 100];
      u._DistortionEnabled = 1;
    }
    if (chroma.intensity > 0) u._Chroma_Params = chroma.intensity * 0.05;
    // Color Lookup：贴图必须是 高² × 高 的横条
    const userLut = this.tex(cl.texture);
    if (cl.contribution > 0 && userLut && userLut.width === userLut.height * userLut.height) {
      u._UserLut = userLut;
      u._UserLut_Params = [1 / userLut.width, 1 / userLut.height, userLut.height - 1, cl.contribution];
    }
    // Film Grain（PostProcessUtils.ConfigureFilmGrain）；URP 每帧随机偏移，这里按时间取伪随机数
    const grainTex = fg.type === 10 ? this.tex(fg.texture) : this.tex(FILM_GRAIN_TEXTURES[fg.type]);
    if (fg.intensity > 0 && grainTex) {
      const fr = (x) => x - Math.floor(x);
      const n = Math.floor(frame.time * 60);
      u._Grain_Texture = grainTex;
      u._Grain_Params = [fg.intensity * 4, fg.response];
      u._Grain_TilingParams = [W / grainTex.width, H / grainTex.height, fr(Math.sin(n * 12.9898 + 1.3) * 43758.5453), fr(Math.sin(n * 78.233 + 2.7) * 43758.5453)];
      u._GrainEnabled = 1;
    }
    const out = frame.getTemporaryRT('uber', W, H, { color: 'RGBA16F' });
    E.blit(src, out, this.mat, 'Uber', u);
    src = out.texture;

    for (const fx of POST_EFFECTS.filter((f) => f.order >= 200).sort((a, b) => a.order - b.order)) src = fx.render(this, frame, src, vol) || src;
    frame.postOutput = src;
  }

  // ColorGradingLutPass：把白平衡、对比度、调色、曲线、色调映射烘焙进 lutSize³ 的 LUT（横条 lutSize² × lutSize）
  buildLut(frame, vol, hdr, lutSize) {
    const E = this.engine;
    const get = (t) => vol[NS + t] || VOLUME_DEFAULTS[NS + t];
    const cm = get('ChannelMixer'), ca = get('ColorAdjustments'), lgg = get('LiftGammaGain'), smh = get('ShadowsMidtonesHighlights');
    const st = get('SplitToning'), tm = get('Tonemapping'), wb = get('WhiteBalance');
    const [shadows, midtones, highlights] = [smh.shadows, smh.midtones, smh.highlights].map(prepareSMH);
    const lutW = lutSize * lutSize;
    const rt = frame.getTemporaryRT('internalLut', lutW, lutSize, { color: 'RGBA16F' });
    E.blit(null, rt, this.mat, hdr ? 'LutBuilderHdr' : 'LutBuilderLdr', {
      _LutBuild_Params: [lutSize, 0.5 / lutW, 0.5 / lutSize, lutSize / (lutSize - 1)],
      _ColorBalance: whiteBalanceLMS(wb.temperature, wb.tint),
      _ColorFilter: [...lin(ca.colorFilter), 0],
      _ChannelMixerRed: [cm.redOutRedIn / 100, cm.redOutGreenIn / 100, cm.redOutBlueIn / 100, 0],
      _ChannelMixerGreen: [cm.greenOutRedIn / 100, cm.greenOutGreenIn / 100, cm.greenOutBlueIn / 100, 0],
      _ChannelMixerBlue: [cm.blueOutRedIn / 100, cm.blueOutGreenIn / 100, cm.blueOutBlueIn / 100, 0],
      _HueSatCon: [ca.hueShift / 360, ca.saturation / 100 + 1, ca.contrast / 100 + 1, 0],
      ...prepareLGG(lgg.lift, lgg.gamma, lgg.gain),
      _Shadows: shadows, _Midtones: midtones, _Highlights: highlights,
      _ShaHiLimits: [smh.shadowsStart, smh.shadowsEnd, smh.highlightsStart, smh.highlightsEnd],
      _SplitShadows: [st.shadows[0], st.shadows[1], st.shadows[2], st.balance / 100],
      _SplitHighlights: [st.highlights[0], st.highlights[1], st.highlights[2], 0],
      _TonemapMode: tm.mode,
      _Curves: this.curveTexture(get('ColorCurves')),
    });
    return rt.texture;
  }

  // 8 条 TextureCurve 各烘焙成 128 个采样（TextureCurve.GetTexture：第 i 个像素 = Evaluate(i / 128)），合成一张 128×8 的贴图
  curveTexture(cc) {
    const names = ['master', 'red', 'green', 'blue', 'hueVsHue', 'hueVsSat', 'satVsSat', 'lumVsSat'];
    const key = JSON.stringify(names.map((n) => cc[n]));
    if (this._curveKey === key) return this._curveTex;
    const data = new Float32Array(128 * 8 * 4);
    names.forEach((n, row) => {
      const c = cc[n] || VOLUME_DEFAULTS[NS + 'ColorCurves'][n];
      for (let i = 0; i < 128; i++) data[(row * 128 + i) * 4] = evaluateTextureCurve(c, i / 128);
    });
    const gl = this.engine.gl;
    if (this._curveTex) gl.deleteTexture(this._curveTex.tex);
    this._curveTex = this.engine.glc.texture2D(128, 8, 'RGBA16F_FROM32', data, { mips: false, filter: 'Bilinear', wrap: 'Clamp' });
    this._curveKey = key;
    return this._curveTex;
  }

  // URP 14 的 Bloom：预过滤 → 逐级降采样（9 tap 高斯，先横后竖）→ 逐级升采样混合
  bloom(frame, src, b, W, H) {
    const E = this.engine;
    let tw = W >> 1, th = H >> 1;
    if (b.downscale === 1) { tw = W >> 2; th = H >> 2; }
    const maxSize = Math.max(tw, th);
    const iterations = Math.floor(Math.log2(maxSize) - 1);
    const mipCount = Math.max(1, Math.min(iterations, b.maxIterations || 6));
    const threshold = srgbToLinear(b.threshold), knee = threshold * 0.5;
    const scatter = 0.05 + (0.95 - 0.05) * b.scatter;
    const params = [scatter, b.clamp, threshold, knee];
    const down = [], up = [];
    for (let i = 0; i < mipCount; i++) {
      const w = Math.max(1, tw >> i), h = Math.max(1, th >> i);
      down.push(frame.getTemporaryRT('bloomDown' + i, w, h, { color: 'RGBA16F' }));
      up.push(frame.getTemporaryRT('bloomUp' + i, w, h, { color: 'RGBA16F' }));
    }
    const hq = b.highQualityFiltering ? 1 : 0;
    E.blit(src, down[0], this.mat, 'BloomPrefilter', { _Params: params, _HighQuality: hq });
    let last = down[0];
    for (let i = 1; i < mipCount; i++) {
      E.blit(last.texture, up[i], this.mat, 'BloomBlurH', { _Params: params });
      E.blit(up[i].texture, down[i], this.mat, 'BloomBlurV', { _Params: params });
      last = down[i];
    }
    for (let i = mipCount - 2; i >= 0; i--) {
      const low = i === mipCount - 2 ? down[i + 1] : up[i + 1];
      const lt = low.texture;
      E.blit(down[i].texture, up[i], this.mat, 'BloomUpsample', { _Params: params, _SourceTexLowMip: lt, _SourceTexLowMip_TexelSize: [1 / lt.width, 1 / lt.height, lt.width, lt.height], _HighQuality: hq });
    }
    return mipCount > 1 ? up[0].texture : down[0].texture;
  }
}

function lin(c) { return [srgbToLinear(c[0]), srgbToLinear(c[1]), srgbToLinear(c[2])]; }
const luminance = (c) => c[0] * 0.2126729 + c[1] * 0.7151522 + c[2] * 0.072175;

// URP ColorUtils.ColorBalanceToLMSCoeffs
function whiteBalanceLMS(temperature, tint) {
  const t1 = temperature / 65, t2 = tint / 65;
  const x = 0.31271 - t1 * (t1 < 0 ? 0.1 : 0.05);
  const y = 2.87 * x - 3 * x * x - 0.27509507 + t2 * 0.05;   // StandardIlluminantY(x) + 色调偏移
  const X = x / y, Z = (1 - x - y) / y;
  const L = 0.7328 * X + 0.4296 - 0.1624 * Z, M = -0.7036 * X + 1.6975 + 0.0061 * Z, S = 0.003 * X + 0.0136 + 0.9834 * Z;
  return [0.949237 / L, 1.03542 / M, 1.08728 / S, 0];
}

// ColorUtils.PrepareShadowsMidtonesHighlights（单个颜色）
function prepareSMH(v) {
  const c = lin(v), w = v[3] * (Math.sign(v[3]) < 0 ? 1 : 4);
  return [Math.max(c[0] + w, 0), Math.max(c[1] + w, 0), Math.max(c[2] + w, 0), 0];
}

// ColorUtils.PrepareLiftGammaGain
function prepareLGG(lift, gamma, gain) {
  const l = lin(lift).map((x) => x * 0.15), lumL = luminance(l);
  const g = lin(gamma).map((x) => x * 0.8), lumG = luminance(g), gw = gamma[3] + 1;
  const n = lin(gain).map((x) => x * 0.8), lumN = luminance(n), nw = gain[3] + 1;
  return {
    _Lift: [...l.map((x) => x - lumL + lift[3]), 0],
    _Gamma: [...g.map((x) => 1 / Math.max(x - lumG + gw, 1e-3)), 0],
    _Gain: [...n.map((x) => x - lumN + nw), 0],
  };
}

// TextureCurve.Evaluate：AnimationCurve 的 Hermite 插值；循环曲线在两端各补一个关键帧
export function evaluateTextureCurve(c, t) {
  let keys = (c.m_Curve || []).map((k) => ({ t: k[0], v: k[1], in: k[2], out: k[3] }));
  if (!keys.length) return c.m_ZeroValue ?? 0;
  if (c.m_Loop && keys.length > 1) {
    const range = c.m_Range || 1, last = keys[keys.length - 1], first = keys[0];
    keys = [{ ...last, t: last.t - range }, ...keys, { ...first, t: first.t + range }];
  }
  if (t <= keys[0].t) return keys[0].v;
  const L = keys[keys.length - 1];
  if (t >= L.t) return L.v;
  let i = 0;
  while (i < keys.length - 2 && t >= keys[i + 1].t) i++;
  const a = keys[i], b = keys[i + 1], dt = b.t - a.t;
  if (dt <= 0) return b.v;
  if (!isFinite(a.out) || !isFinite(b.in)) return a.v;   // 阶梯切线
  const s = (t - a.t) / dt, s2 = s * s, s3 = s2 * s;
  return (2 * s3 - 3 * s2 + 1) * a.v + (s3 - 2 * s2 + s) * a.out * dt + (-2 * s3 + 3 * s2) * b.v + (s3 - s2) * b.in * dt;
}
