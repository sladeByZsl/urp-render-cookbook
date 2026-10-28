// 颜色分级与色调映射：对应 URP 的 LutBuilderHdr.shader / LutBuilderLdr.shader + Color.hlsl + ACES.hlsl，
// 以及 UberPost 里的 ApplyColorGrading（查内部 LUT、用户 LUT）。
// 和 URP 一样分两步：先把所有调色 + 色调映射“烘焙”进一张 32³ 的 LUT（横条 1024×32），Uber 里再按像素查表。
//   HDR 分级模式：LUT 的输入是 LogC 编码（可表示 0~58.85 的 HDR 值），输出已经过色调映射；
//                选 ACES 时整个分级在 ACEScg（AP1）空间里做（和 URP 一致）。
//   LDR 分级模式：Uber 里先色调映射并截到 [0,1]，LUT 输入是线性 0~1。

// ---- LUT 生成用的参数（名字与 URP 相同） ----
uniform vec4 _ColorBalance;      // 白平衡的 LMS 系数
uniform vec4 _ColorFilter;       // 线性颜色
uniform vec4 _ChannelMixerRed;   // 通道混合器（/100）
uniform vec4 _ChannelMixerGreen;
uniform vec4 _ChannelMixerBlue;
uniform vec4 _HueSatCon;         // (色相偏移/360, 饱和度/100+1, 对比度/100+1, 0)
uniform vec4 _Lift;
uniform vec4 _Gamma;
uniform vec4 _Gain;
uniform vec4 _Shadows;
uniform vec4 _Midtones;
uniform vec4 _Highlights;
uniform vec4 _ShaHiLimits;       // (阴影起, 阴影止, 高光起, 高光止)
uniform vec4 _SplitShadows;      // rgb 颜色，w = balance/100
uniform vec4 _SplitHighlights;
uniform float _TonemapMode;      // 0 无，1 Neutral，2 ACES
// URP 每条曲线一张 128×1 的贴图；这里合成一张 128×8：
// 行 0 Master，1 Red，2 Green，3 Blue，4 HueVsHue，5 HueVsSat，6 SatVsSat，7 LumVsSat
uniform sampler2D _Curves;

#define ACEScc_MIDGRAY 0.4135884
#ifndef HALF_MAX
#define HALF_MAX 65504.0
#endif

// ---- LogC（ARRI Alexa El 1000），URP 用它做对比度和 LUT 的空间（URP 默认用非精确版本） ----
const float LogC_cut = 0.011361, LogC_a = 5.555556, LogC_b = 0.047996, LogC_c = 0.244161, LogC_d = 0.386036, LogC_e = 5.301883, LogC_f = 0.092819;
vec3 LinearToLogC(vec3 x) { return LogC_c * log(max(LogC_a * x + LogC_b, 0.0)) / log(10.0) + LogC_d; }
vec3 LogCToLinear(vec3 x) { return (pow(vec3(10.0), (x - LogC_d) / LogC_c) - LogC_b) / LogC_a; }

vec3 RgbToHsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-4;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}
vec3 HsvToRgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, saturate(p - K.xxx), c.y);
}
float RotateHue(float v, float lo, float hi) { return v < lo ? v + hi : v > hi ? v - hi : v; }

// 线性 sRGB ↔ LMS（白平衡）
vec3 LinearToLMS(vec3 c) {
    const mat3 LIN_2_LMS = mat3(3.90405e-1, 7.08416e-2, 2.31082e-2, 5.49941e-1, 9.63172e-1, 1.28021e-1, 8.92632e-3, 1.35775e-3, 9.36245e-1);
    return LIN_2_LMS * c;
}
vec3 LMSToLinear(vec3 c) {
    const mat3 LMS_2_LIN = mat3(2.85847e+0, -2.10182e-1, -4.18120e-2, -1.62879e+0, 1.15820e+0, -1.18169e-1, -2.48910e-2, 3.24281e-4, 1.06867e+0);
    return LMS_2_LIN * c;
}

// 分离色调用的“柔光”混合
vec3 SoftLight(vec3 base, vec3 blend) {
    vec3 r1 = 2.0 * base * blend + base * base * (1.0 - 2.0 * blend);
    vec3 r2 = sqrt(base) * (2.0 * blend - 1.0) + 2.0 * base * (1.0 - blend);
    vec3 t = step(0.5, blend);
    return r2 * t + (1.0 - t) * r1;
}
float Max3(float a, float b, float c) { return max(a, max(b, c)); }
vec3 FastTonemap(vec3 c) { return c / (Max3(c.r, c.g, c.b) + 1.0); }
vec3 FastTonemapInvert(vec3 c) { return c / (1.0 - Max3(c.r, c.g, c.b)); }

// ---- Neutral 色调映射（John Hable / URP NeutralTonemap） ----
vec3 NeutralCurve(vec3 x, float a, float b, float c, float d, float e, float f) {
    return ((x * (a * x + c * b) + d * e) / (x * (a * x + b) + d * f)) - e / f;
}
vec3 NeutralTonemap(vec3 x) {
    const float a = 0.2, b = 0.29, c = 0.24, d = 0.272, e = 0.02, f = 0.3, whiteLevel = 5.3, whiteClip = 1.0;
    vec3 whiteScale = vec3(1.0) / NeutralCurve(vec3(whiteLevel), a, b, c, d, e, f);
    x = NeutralCurve(x * whiteScale, a, b, c, d, e, f);
    x *= whiteScale;
    x /= whiteClip;
    return x;
}

// ---- ACES（URP ACES.hlsl：RRT + ODT，色调曲线用拟合版本） ----
// GLSL 的 mat3 按列填写，下面的矩阵都写成转置，乘法写成 v * M 等价于 HLSL 的 mul(M, v)
const mat3 sRGB_2_AP0 = mat3(0.4397010, 0.3829780, 0.1773350, 0.0897923, 0.8134230, 0.0967616, 0.0175440, 0.1115440, 0.8707040);
const mat3 AP0_2_AP1_MAT = mat3(1.4514393161, -0.2365107469, -0.2149285693, -0.0765537734, 1.1762296998, -0.0996759264, 0.0083161484, -0.0060324498, 0.9977163014);
const mat3 AP1_2_AP0_MAT = mat3(0.6954522414, 0.1406786965, 0.1638690622, 0.0447945634, 0.8596711185, 0.0955343182, -0.0055258826, 0.0040252103, 1.0015006723);
const mat3 AP1_2_XYZ_MAT = mat3(0.6624541811, 0.1340042065, 0.1561876870, 0.2722287168, 0.6740817658, 0.0536895174, -0.0055746495, 0.0040607335, 1.0103391003);
const mat3 XYZ_2_AP1_MAT = mat3(1.6410233797, -0.3248032942, -0.2364246952, -0.6636628587, 1.6153315917, 0.0167563477, 0.0117218943, -0.0082844420, 0.9883948585);
const mat3 D60_2_D65_CAT = mat3(0.98722400, -0.00611327, 0.01595330, -0.00759836, 1.00186000, 0.00533002, 0.00307257, -0.00509595, 1.08168000);
const mat3 XYZ_2_REC709_MAT = mat3(3.2409699419, -1.5373831776, -0.4986107603, -0.9692436363, 1.8759675015, 0.0415550574, 0.0556300797, -0.2039769589, 1.0569715142);
const vec3 AP1_RGB2Y = vec3(0.272229, 0.674082, 0.0536895);

vec3 unity_to_ACES(vec3 x) { return x * sRGB_2_AP0; }
vec3 ACES_to_ACEScg(vec3 x) { return x * AP0_2_AP1_MAT; }
vec3 ACEScg_to_ACES(vec3 x) { return x * AP1_2_AP0_MAT; }
float ACES_to_ACEScc_fast(float x) { return x < 0.00003051757 ? (log2(0.00001525878 + x * 0.5) + 9.72) / 17.52 : (log2(x) + 9.72) / 17.52; }
vec3 ACES_to_ACEScc(vec3 x) {
    x = clamp(x, 0.0, HALF_MAX);
    return vec3(ACES_to_ACEScc_fast(x.r), ACES_to_ACEScc_fast(x.g), ACES_to_ACEScc_fast(x.b));
}
float ACEScc_to_ACES1(float x) {
    if (x < -0.3013698630) return (pow(2.0, x * 17.52 - 9.72) - pow(2.0, -16.0)) * 2.0;
    else if (x < (log2(HALF_MAX) + 9.72) / 17.52) return pow(2.0, x * 17.52 - 9.72);
    return HALF_MAX;
}
vec3 ACEScc_to_ACES(vec3 x) { return vec3(ACEScc_to_ACES1(x.r), ACEScc_to_ACES1(x.g), ACEScc_to_ACES1(x.b)); }

float rgb_2_saturation(vec3 rgb) {
    float mi = min(rgb.r, min(rgb.g, rgb.b)), ma = max(rgb.r, max(rgb.g, rgb.b));
    return (max(ma, 1e-4) - max(mi, 1e-4)) / max(ma, 1e-2);
}
float rgb_2_yc(vec3 rgb) {
    float r = rgb.x, g = rgb.y, b = rgb.z;
    float chroma = sqrt(max(b * (b - g) + g * (g - r) + r * (r - b), 0.0));
    return (b + g + r + 1.75 * chroma) / 3.0;
}
float sigmoid_shaper(float x) {
    float t = max(1.0 - abs(x / 2.0), 0.0);
    float y = 1.0 + sign(x) * (1.0 - t * t);
    return y / 2.0;
}
float glow_fwd(float ycIn, float glowGainIn, float glowMid) {
    if (ycIn <= 2.0 / 3.0 * glowMid) return glowGainIn;
    if (ycIn >= 2.0 * glowMid) return 0.0;
    return glowGainIn * (glowMid / ycIn - 0.5);
}
float rgb_2_hue(vec3 rgb) {
    if (rgb.x == rgb.y && rgb.y == rgb.z) return 0.0;
    float hue = (180.0 / PI) * atan(sqrt(3.0) * (rgb.y - rgb.z), 2.0 * rgb.x - rgb.y - rgb.z);
    return hue < 0.0 ? hue + 360.0 : hue;
}
float center_hue(float hue, float centerH) {
    float h = hue - centerH;
    if (h < -180.0) h += 360.0; else if (h > 180.0) h -= 360.0;
    return h;
}
vec3 darkSurround_to_dimSurround(vec3 linearCV) {
    vec3 XYZ = linearCV * AP1_2_XYZ_MAT;
    float s = max(XYZ.x + XYZ.y + XYZ.z, 1e-10);
    vec3 xyY = vec3(XYZ.x / s, XYZ.y / s, XYZ.y);
    xyY.z = pow(clamp(xyY.z, 0.0, 65504.0), 0.9811);
    XYZ = vec3(xyY.x * xyY.z / max(xyY.y, 1e-10), xyY.z, (1.0 - xyY.x - xyY.y) * xyY.z / max(xyY.y, 1e-10));
    return XYZ * XYZ_2_AP1_MAT;
}
vec3 AcesTonemap(vec3 aces) {
    float saturation = rgb_2_saturation(aces);
    float ycIn = rgb_2_yc(aces);
    float s = sigmoid_shaper((saturation - 0.4) / 0.2);
    float addedGlow = 1.0 + glow_fwd(ycIn, 0.05 * s, 0.08);
    aces *= addedGlow;
    float hue = rgb_2_hue(aces);
    float centeredHue = center_hue(hue, 0.0);
    float hueWeight = smoothstep(0.0, 1.0, 1.0 - abs(2.0 * centeredHue / 135.0));
    hueWeight *= hueWeight;
    aces.r += hueWeight * saturation * (0.03 - aces.r) * (1.0 - 0.82);
    aces = clamp(aces, 0.0, 65504.0);
    vec3 rgbPre = clamp(aces * AP0_2_AP1_MAT, 0.0, 65504.0);
    rgbPre = mix(vec3(dot(rgbPre, AP1_RGB2Y)), rgbPre, 0.96);
    const float a = 278.5085, b = 10.7772, c = 293.6045, d = 88.7122, e = 80.6889;
    vec3 x = rgbPre;
    vec3 rgbPost = (x * (a * x + b)) / (x * (c * x + d) + e);
    vec3 linearCV = darkSurround_to_dimSurround(rgbPost);
    linearCV = mix(vec3(dot(linearCV, AP1_RGB2Y)), linearCV, 0.93);
    vec3 XYZ = linearCV * AP1_2_XYZ_MAT;
    XYZ = XYZ * D60_2_D65_CAT;
    return XYZ * XYZ_2_REC709_MAT;
}

// ---- 曲线：对应 URP 的 EvaluateCurve(curveTex, t)（128 像素贴图 + 双线性） ----
float EvaluateCurve(float row, float t) { return saturate(texture(_Curves, vec2(t, (row + 0.5) / 8.0)).x); }

// URP Common.hlsl 的 GetLuminance：ACES 分级时在 AP1 空间求亮度
float GetLuminanceHdr(vec3 c) { return _TonemapMode > 1.5 ? dot(c, AP1_RGB2Y) : Luminance(c); }

// 分离色调 → 通道混合 → 阴影/中间调/高光 → Lift/Gamma/Gain → HSV 曲线、色相、饱和度（HDR 和 LDR 两个 LUT 共用这一段）
vec3 ColorGradeCommon(vec3 colorLinear, bool aces)
{
    // Split toning：和 Adobe 一样在 gamma 空间里做
    float balance = _SplitShadows.w;
    vec3 colorGamma = PositivePow(colorLinear, 1.0 / 2.2);
    float luma = saturate((aces ? dot(saturate(colorGamma), AP1_RGB2Y) : Luminance(saturate(colorGamma))) + balance);
    vec3 splitShadows = mix(vec3(0.5), _SplitShadows.xyz, 1.0 - luma);
    vec3 splitHighlights = mix(vec3(0.5), _SplitHighlights.xyz, luma);
    colorGamma = SoftLight(colorGamma, splitShadows);
    colorGamma = SoftLight(colorGamma, splitHighlights);
    colorLinear = PositivePow(colorGamma, 2.2);

    // Channel mixing（Adobe 风格）
    colorLinear = vec3(dot(colorLinear, _ChannelMixerRed.xyz), dot(colorLinear, _ChannelMixerGreen.xyz), dot(colorLinear, _ChannelMixerBlue.xyz));

    // Shadows, midtones, highlights
    luma = aces ? dot(colorLinear, AP1_RGB2Y) : Luminance(colorLinear);
    float shadowsFactor = 1.0 - smoothstep(_ShaHiLimits.x, _ShaHiLimits.y, luma);
    float highlightsFactor = smoothstep(_ShaHiLimits.z, _ShaHiLimits.w, luma);
    float midtonesFactor = 1.0 - shadowsFactor - highlightsFactor;
    colorLinear = colorLinear * _Shadows.xyz * shadowsFactor
                + colorLinear * _Midtones.xyz * midtonesFactor
                + colorLinear * _Highlights.xyz * highlightsFactor;

    // Lift, gamma, gain
    colorLinear = colorLinear * _Gain.xyz + _Lift.xyz;
    colorLinear = sign(colorLinear) * pow(abs(colorLinear), _Gamma.xyz);

    // HSV operations
    vec3 hsv = RgbToHsv(colorLinear);
    float satMult = EvaluateCurve(5.0, hsv.x) * 2.0;                        // Hue Vs Sat
    satMult *= EvaluateCurve(6.0, hsv.y) * 2.0;                             // Sat Vs Sat
    satMult *= EvaluateCurve(7.0, Luminance(colorLinear)) * 2.0;            // Lum Vs Sat
    float hue = hsv.x + _HueSatCon.x;                                       // Hue Shift & Hue Vs Hue
    float offset = EvaluateCurve(4.0, hue) - 0.5;
    hue += offset;
    hsv.x = RotateHue(hue, 0.0, 1.0);
    colorLinear = HsvToRgb(hsv);

    // Global saturation
    luma = aces ? dot(colorLinear, AP1_RGB2Y) : Luminance(colorLinear);
    colorLinear = vec3(luma) + (_HueSatCon.yyy * satMult) * (colorLinear - vec3(luma));
    return colorLinear;
}

vec3 YRGBCurves(vec3 c)
{
    const float kHalfPixel = (1.0 / 128.0) / 2.0;
    c += kHalfPixel;
    c = vec3(EvaluateCurve(0.0, c.r), EvaluateCurve(0.0, c.g), EvaluateCurve(0.0, c.b));   // Y (master)
    c += kHalfPixel;
    return vec3(EvaluateCurve(1.0, c.r), EvaluateCurve(2.0, c.g), EvaluateCurve(3.0, c.b)); // RGB
}

// LutBuilderHdr 的 ColorGrade：输入是 LogC 编码的 LUT 坐标
vec3 ColorGradeHdr(vec3 colorLutSpace)
{
    bool aces = _TonemapMode > 1.5;
    vec3 colorLinear = LogCToLinear(colorLutSpace);
    // White balance in LMS space
    colorLinear = LMSToLinear(LinearToLMS(colorLinear) * _ColorBalance.xyz);
    // Do contrast in log after white balance（ACES 时在 ACEScc 里做，之后转到 ACEScg）
    vec3 colorLog = aces ? ACES_to_ACEScc(unity_to_ACES(colorLinear)) : LinearToLogC(colorLinear);
    colorLog = (colorLog - ACEScc_MIDGRAY) * _HueSatCon.z + ACEScc_MIDGRAY;
    colorLinear = aces ? ACES_to_ACEScg(ACEScc_to_ACES(colorLog)) : LogCToLinear(colorLog);
    // Color filter is just an unclipped multiplier
    colorLinear *= _ColorFilter.xyz;
    colorLinear = max(vec3(0.0), colorLinear);
    colorLinear = ColorGradeCommon(colorLinear, aces);
    // YRGB 曲线要求 [0,1]，先用 FastTonemap 压进来，查完再还原
    colorLinear = FastTonemap(colorLinear);
    colorLinear = YRGBCurves(colorLinear);
    colorLinear = FastTonemapInvert(colorLinear);
    return max(vec3(0.0), colorLinear);
}
vec3 TonemapHdr(vec3 colorLinear)
{
    if (_TonemapMode > 1.5) return AcesTonemap(ACEScg_to_ACES(colorLinear));   // 输入其实是 ACEScg
    if (_TonemapMode > 0.5) return NeutralTonemap(colorLinear);
    return colorLinear;
}

// LutBuilderLdr：输入是已经色调映射过的线性 0~1 颜色
vec3 ColorGradeLdr(vec3 colorLinear)
{
    colorLinear = LMSToLinear(LinearToLMS(colorLinear) * _ColorBalance.xyz);
    vec3 colorLog = LinearToLogC(colorLinear);
    colorLog = (colorLog - ACEScc_MIDGRAY) * _HueSatCon.z + ACEScc_MIDGRAY;
    colorLinear = LogCToLinear(colorLog);
    colorLinear *= _ColorFilter.xyz;
    colorLinear = max(vec3(0.0), colorLinear);
    colorLinear = ColorGradeCommon(colorLinear, false);
    colorLinear = YRGBCurves(colorLinear);
    return saturate(colorLinear);
}

// ---- LUT 横条的读写（Color.hlsl） ----
// params = (lut_height, 0.5 / lut_width, 0.5 / lut_height, lut_height / (lut_height - 1))
vec3 GetLutStripValue(vec2 uv, vec4 params)
{
    uv.x *= params.x;
    float lutBase = floor(uv.x);
    uv.x -= lutBase;
    float lutBaseU = lutBase * 2.0 * params.z;
    vec3 color;
    color.rg = uv - params.zz;
    color.b = lutBaseU;
    return color * params.w;
}
// scaleOffset = (1 / lut_width, 1 / lut_height, lut_height - 1)
vec3 ApplyLut2D(sampler2D tex, vec3 uvw, vec3 scaleOffset)
{
    uvw.z *= scaleOffset.z;
    float shift = floor(uvw.z);
    uvw.xy = uvw.xy * scaleOffset.z * scaleOffset.xy + scaleOffset.xy * 0.5;
    uvw.x += shift * scaleOffset.y;
    return mix(textureLod(tex, uvw.xy, 0.0).rgb, textureLod(tex, uvw.xy + vec2(scaleOffset.y, 0.0), 0.0).rgb, uvw.z - shift);
}

// ---- Uber 里的 ApplyColorGrading（URP PostProcessing/Common.hlsl） ----
uniform float _PostExposure;     // exp2(曝光)
uniform float _HDRGrading;       // 1 = HDR 分级模式
uniform sampler2D _InternalLut;
uniform vec4 _Lut_Params;        // (1/lut_width, 1/lut_height, lut_height-1, 0)
uniform sampler2D _UserLut;
uniform vec4 _UserLut_Params;    // (1/宽, 1/高, 高-1, 贡献度)

vec3 ApplyTonemapLdr(vec3 c)
{
    if (_TonemapMode > 1.5) c = AcesTonemap(unity_to_ACES(c));
    else if (_TonemapMode > 0.5) c = NeutralTonemap(c);
    return saturate(c);
}

vec3 ApplyColorGrading(vec3 inputColor)
{
    // Artist request to fine tune exposure in post without affecting bloom, dof etc
    inputColor *= _PostExposure;
    if (_HDRGrading > 0.5)
    {
        // HDR：查内部 LogC LUT，（可选）再截断后查用户 LUT
        vec3 inputLutSpace = saturate(LinearToLogC(inputColor));
        inputColor = ApplyLut2D(_InternalLut, inputLutSpace, _Lut_Params.xyz);
        if (_UserLut_Params.w > 0.0)
        {
            inputColor = saturate(inputColor);
            inputColor = LinearToSRGB(inputColor);   // 用户 LUT 在 sRGB 空间里查
            vec3 outLut = ApplyLut2D(_UserLut, inputColor, _UserLut_Params.xyz);
            inputColor = mix(inputColor, outLut, _UserLut_Params.w);
            inputColor = SRGBToLinear(inputColor);
        }
    }
    else
    {
        // LDR：先色调映射（截到 0~1），（可选）查用户 LUT，再查内部线性 LUT
        inputColor = ApplyTonemapLdr(inputColor);
        if (_UserLut_Params.w > 0.0)
        {
            inputColor = LinearToSRGB(inputColor);
            vec3 outLut = ApplyLut2D(_UserLut, inputColor, _UserLut_Params.xyz);
            inputColor = mix(inputColor, outLut, _UserLut_Params.w);
            inputColor = SRGBToLinear(inputColor);
        }
        inputColor = ApplyLut2D(_InternalLut, inputColor, _Lut_Params.xyz);
    }
    return inputColor;
}
