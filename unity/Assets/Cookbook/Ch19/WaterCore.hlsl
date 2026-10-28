// 第 19 章：风格化水面的全部“积木”。Water.shader 按关键字把它们拼起来。
// 每个函数对应正文里的一个案例：深度 → 折射 → 法线 → 反射 → 高光 → 泡沫 → 焦散 → Gerstner 波。
#ifndef COOKBOOK_CH19_WATER_CORE_INCLUDED
#define COOKBOOK_CH19_WATER_CORE_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"

TEXTURE2D(_NormalMap);  SAMPLER(sampler_NormalMap);
TEXTURE2D(_FoamNoise);  SAMPLER(sampler_FoamNoise);
// 平面反射 RT 由 C# 的 PlanarReflection 组件设成全局纹理，不属于材质，不放进 CBUFFER
TEXTURE2D(_PlanarReflectionTex); SAMPLER(sampler_PlanarReflectionTex);

CBUFFER_START(UnityPerMaterial)
    // 深度着色
    half4  _ShallowColor;
    half4  _DeepColor;
    float  _DepthMax;
    half4  _Absorption;        // 每米吸收系数（RGB 分开），用于 Beer-Lambert
    float  _EdgeFade;
    // 折射
    half   _RefractionStrength;
    half   _RefractLeakFix;
    // 法线
    float4 _NormalTiling;      // xy：两层法线的平铺（每米几次）
    float4 _FlowA;             // xy：第一层流向*速度，z：强度
    float4 _FlowB;
    // 反射
    half   _ReflectionStrength;
    half   _UseFresnel;
    half   _Roughness;
    half   _PlanarDistortion;
    // 高光
    half   _SpecPower;
    half   _SpecIntensity;
    // 泡沫
    half4  _FoamColor;
    float  _FoamDistance;
    float  _FoamTiling;
    half   _FoamSoftness;
    // 焦散
    float  _CausticScale;
    half   _CausticIntensity;
    float  _CausticDepthFade;
    half   _CausticSplit;
    // Gerstner 波：xy 方向，z 陡度，w 波长（米）
    float4 _WaveA;
    float4 _WaveB;
    float4 _WaveC;
    // 时间与调试
    half   _AutoPlay;
    float  _Phase;
    half   _DebugView;
CBUFFER_END

float WaterTime() { return _AutoPlay > 0.5 ? _Time.y : _Phase; }

float2 Hash22(float2 p)
{
    float3 p3 = frac(float3(p.xyx) * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.xx + p3.yz) * p3.zy);
}

//#region gerstner
// 单个 Gerstner 波。wave = (方向x, 方向z, 陡度 Q, 波长 L)。累加位移，同时累加切线/副切线用于求法线。
// 推导见第 17 章：k = 2π/L，相速度 c = sqrt(g/k)，振幅 a = Q/k（Q=1 时波峰刚好变尖）
float3 GerstnerWave(float4 wave, float3 p, float t, inout float3 tangent, inout float3 binormal)
{
    float steep = wave.z;
    float k = 2.0 * PI / wave.w;
    float c = sqrt(9.8 / k);
    float2 d = normalize(wave.xy);
    float f = k * (dot(d, p.xz) - c * t);
    float a = steep / k;
    float s = sin(f), co = cos(f);

    tangent  += float3(-d.x * d.x * steep * s, d.x * steep * co, -d.x * d.y * steep * s);
    binormal += float3(-d.x * d.y * steep * s, d.y * steep * co, -d.y * d.y * steep * s);
    return float3(d.x * a * co, a * s, d.y * a * co);
}
//#endregion

//#region depth
// 水下深度：用水面这个像素的屏幕 UV 取场景深度，重建出水底的世界坐标
struct WaterDepth
{
    float3 sceneWS;     // 水底（或水中物体）表面的世界坐标
    float  vertical;    // 竖直水深 = 水面 y - 水底 y（与视角无关）
    float  path;        // 视线在水里走过的距离（与视角有关，斜看时更长）
    float  sceneEye;    // 场景的观察空间深度
};

WaterDepth SampleWaterDepth(float2 uv, float3 surfaceWS)
{
    WaterDepth o;
    float raw = SampleSceneDepth(uv);
    o.sceneWS = ComputeWorldSpacePosition(uv, raw, UNITY_MATRIX_I_VP);
    o.vertical = surfaceWS.y - o.sceneWS.y;
    o.path = distance(o.sceneWS, surfaceWS);
    o.sceneEye = LinearEyeDepth(raw, _ZBufferParams);
    return o;
}
//#endregion

//#region normals
// 双层法线：同一张 water_normal 以不同尺度、不同方向流动，两层叠加打破重复感
half3 DualNormalTS(float2 xz, float t)
{
    float2 uvA = xz * _NormalTiling.x + _FlowA.xy * t;
    float2 uvB = xz * _NormalTiling.y + _FlowB.xy * t;
    half3 nA = UnpackNormalScale(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, uvA), _FlowA.z);
    half3 nB = UnpackNormalScale(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, uvB), _FlowB.z);
    // Whiteout 混合：xy 相加、z 相乘，比简单平均保留更多细节（第 7 章有对比）
    return normalize(half3(nA.xy + nB.xy, nA.z * nB.z));
}
//#endregion

//#region refraction
// 折射：按法线扰动屏幕 UV；如果扰动后取到的是“水面之上的东西”（深度比水面还近），说明发生了前景泄漏，退回原 UV
float2 RefractUV(float2 screenUV, half3 normalTS, float surfaceEye, float verticalDepth)
{
    // 越浅扰动越小：岸边几厘米深的水不该把岸上的东西扭得很厉害
    float2 offset = normalTS.xy * _RefractionStrength * saturate(verticalDepth * 2.0);
    // 远处的水在屏幕上更小，同样的偏移量会显得更夸张，除以深度做个近似的透视补偿
    offset /= max(1.0, surfaceEye * 0.25);
    float2 uv = screenUV + offset;
    if (_RefractLeakFix > 0.5)
    {
        float eye = LinearEyeDepth(SampleSceneDepth(uv), _ZBufferParams);
        if (eye < surfaceEye) uv = screenUV;
    }
    return uv;
}
//#endregion

//#region absorption
// Beer-Lambert：光在水里每走 1 米，各通道按 exp(-σ) 衰减。红光衰减最快，所以深水偏蓝绿。
// 被吸收掉的部分用“散射色”补上（水体本身被照亮的颜色）
half3 UnderwaterColor(half3 sceneColor, float pathLength, half3 scatterColor)
{
    half3 transmittance = exp(-_Absorption.rgb * pathLength);
    return sceneColor * transmittance + scatterColor * (1.0h - transmittance);
}
//#endregion

//#region fresnel
// Schlick 菲涅尔。水的折射率约 1.33，F0 = ((1.33-1)/(1.33+1))² ≈ 0.02：正看几乎全透，掠射角几乎全反
half WaterFresnel(half3 normalWS, half3 viewWS)
{
    half NdotV = saturate(dot(normalWS, viewWS));
    return 0.02h + 0.98h * pow(1.0h - NdotV, 5.0h);
}
//#endregion

//#region specular
// 太阳高光：Blinn-Phong，指数很高（水面很光滑），乘上阴影，让高光不会出现在柱子的影子里
half3 SunSpecular(Light light, half3 normalWS, half3 viewWS)
{
    half3 h = SafeNormalize(light.direction + viewWS);
    half spec = pow(saturate(dot(normalWS, h)), _SpecPower);
    // 能量归一化的近似系数 (n+8)/(8π)，让指数变大时高光变小但更亮（第 5 章）
    spec *= (_SpecPower + 8.0h) / (8.0h * PI);
    return light.color * spec * _SpecIntensity * light.shadowAttenuation;
}
//#endregion

//#region foam
// 岸边泡沫 = 贴岸的一条实心带 + 一圈圈向岸边推进的细线，都用噪声打散
half ShoreFoam(float2 xz, float verticalDepth, half3 normalTS, float t)
{
    half shore = saturate(verticalDepth / _FoamDistance);          // 0 在岸线，1 在泡沫带外沿
    float2 uv = xz * _FoamTiling + normalTS.xy * 0.1 + float2(t * 0.02, t * 0.015);
    half n = SAMPLE_TEXTURE2D(_FoamNoise, sampler_FoamNoise, uv).r;

    // ① 实心带：阈值被噪声上下扰动，边缘呈不规则的锯齿
    half core = 1.0h - smoothstep(0.25h - _FoamSoftness, 0.25h + _FoamSoftness, shore + (n - 0.5h) * 0.35h);
    // ② 推进线：shore 是“离岸距离”，减去时间就得到一圈圈朝岸边移动的等深线
    half ripple = frac(shore * 2.5h - t * 0.3h + n * 0.6h);
    half lines = smoothstep(0.8h, 0.9h, ripple) * step(0.45h, n) * (1.0h - shore);
    return saturate(core + lines);
}
//#endregion

//#region caustics
// 程序化焦散：Voronoi 的 F2-F1 在细胞边界处接近 0，取反后就是一张亮线网，很像焦散的光网
float2 VoronoiF1F2(float2 p, float t)
{
    float2 cell = floor(p), f = frac(p);
    float F1 = 8.0, F2 = 8.0;
    [unroll] for (int j = -1; j <= 1; j++)
    [unroll] for (int i = -1; i <= 1; i++)
    {
        float2 g = float2(i, j);
        float2 o = Hash22(cell + g);
        o = 0.5 + 0.45 * sin(t + 6.2831 * o);      // 特征点绕各自中心转圈，图案就“活”了
        float2 r = g + o - f;
        float d = dot(r, r);
        if (d < F1) { F2 = F1; F1 = d; }
        else if (d < F2) { F2 = d; }
    }
    return sqrt(float2(F1, F2));
}

half CausticPattern(float2 p, float t)
{
    float2 v1 = VoronoiF1F2(p, t);
    float2 v2 = VoronoiF1F2(p * 1.43 + 7.1, t * 1.21);
    half c1 = 1.0h - smoothstep(0.0h, 0.18h, v1.y - v1.x);
    half c2 = 1.0h - smoothstep(0.0h, 0.18h, v2.y - v2.x);
    // 两层叠加：交叉处更亮，形成焦散特有的“亮节点”
    return c1 * c1 + c2 * c2 + 2.0h * c1 * c2;
}

// 把焦散投到水下表面：沿主光方向把水底点“投影回”水面，在那里查图案，图案就会随太阳方向偏移
half3 Caustics(float3 sceneWS, float verticalDepth, half upFacing, Light light, float t)
{
    float3 L = light.direction;
    float2 p = sceneWS.xz + L.xz / max(L.y, 0.2) * verticalDepth;
    p *= _CausticScale;
    // RGB 三个通道错开一点点采样，模拟不同波长折射角不同产生的色散
    float2 split = float2(_CausticSplit, _CausticSplit * 0.5);
    half3 c = half3(CausticPattern(p + split, t), CausticPattern(p, t), CausticPattern(p - split, t));
    // 刚入水时焦散还没聚焦，太深又被吸收：用两个衰减把它限制在“中间深度”
    half fade = saturate(verticalDepth * 4.0) * exp(-verticalDepth / _CausticDepthFade);
    // 只有朝上的面才接到焦散（upFacing 由调用方用屏幕导数求出，见 SceneUpFacing）
    fade *= upFacing;
    // 阴影要在水底那一点上查：柱子的影子里不该有焦散
    half shadow = MainLightRealtimeShadow(TransformWorldToShadowCoord(sceneWS));
    return c * fade * _CausticIntensity * light.color * shadow;
}
//#endregion

//#region upfacing
// 用重建坐标的屏幕导数求水下表面的法线：ddx/ddy 是相邻像素的世界坐标差，叉积就是面法线。
// 屏幕 y 方向在不同平台可能相反，叉积符号会翻转，所以取绝对值。要用“未折射”的坐标：
// 折射后的 UV 每个像素扰动不同，求出的导数全是噪声
half SceneUpFacing(float3 sceneWS)
{
    float3 n = normalize(cross(ddy(sceneWS), ddx(sceneWS)));
    return saturate(abs(n.y) * 1.5 - 0.3);
}
//#endregion

#endif
