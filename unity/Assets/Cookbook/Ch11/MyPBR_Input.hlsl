// MyPBR 的材质输入：属性 CBUFFER、贴图声明、从贴图读出“表面参数”。
// 这里只做“读数据”，不做任何光照计算。
#ifndef COOKBOOK_MYPBR_INPUT_INCLUDED
#define COOKBOOK_MYPBR_INPUT_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Packing.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"   // LerpWhiteTo 等

//#region cbuffer
// 所有材质属性（贴图除外）都放进 UnityPerMaterial，且每个 Pass 看到的布局完全一致，
// 这是 SRP Batcher 兼容的硬条件。贴图本身不进 CBUFFER，但 _ST 要进。
CBUFFER_START(UnityPerMaterial)
    float4 _BaseMap_ST;
    half4  _BaseColor;
    half   _Metallic;
    half   _Smoothness;
    half   _OcclusionStrength;
    half   _BumpScale;
    half4  _EmissionColor;
    half   _Cutoff;
    half   _EnergyCompensation;   // 0 = 只算单次散射，1 = 加多次散射能量补偿
    half   _SpecularOcclusion;    // 0 = 关，1 = 用 AO 推算镜面遮蔽
CBUFFER_END

TEXTURE2D(_BaseMap);      SAMPLER(sampler_BaseMap);
TEXTURE2D(_MaskMap);      // R 金属度  G AO  A 光滑度（与配套贴图约定一致）
TEXTURE2D(_BumpMap);      SAMPLER(sampler_BumpMap);
TEXTURE2D(_EmissionMap);
TEXTURE2D(_DFGLut);       // 程序生成的环境 BRDF 查找表（RG = A, B），用全局的 sampler_LinearClamp
// Mask 与自发光借用 _BaseMap 的采样器：平铺/过滤方式一样，省采样器槽位（部分平台上限 16 个）。
// 法线贴图单独一个采样器：DepthNormals Pass 只采法线不采基础色，
// 若借用 sampler_BaseMap，_BaseMap 被编译器优化掉后 Metal 会报“采样器找不到贴图”。
//#endregion

//#region surface
// 表面参数：全部在“线性空间、物理含义明确”的单位下
struct MySurface
{
    half3 albedo;               // 基础色（金属时就是 F0 的颜色）
    half  alpha;
    half  metallic;
    half  perceptualRoughness;  // 感知粗糙度 = 1 - smoothness，美术直接调的那个值
    half  occlusion;            // 材质 AO（只影响间接光）
    half3 normalTS;             // 切线空间法线
    half3 emission;
};

MySurface MySampleSurface(float2 uv)
{
    MySurface s;
    half4 base = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uv) * _BaseColor;
    s.albedo = base.rgb;
    s.alpha  = base.a;
#if defined(_ALPHATEST_ON)
    clip(s.alpha - _Cutoff);
#endif

#if defined(_MASKMAP)
    half4 mask = SAMPLE_TEXTURE2D(_MaskMap, sampler_BaseMap, uv);
    s.metallic   = mask.r;                       // 有 Mask 时金属度完全由贴图决定（与 URP Lit 一致）
    half smooth  = mask.a * _Smoothness;         // 光滑度 = 贴图 × 滑条，滑条当总强度用
    s.occlusion  = LerpWhiteTo(mask.g, _OcclusionStrength);
#else
    s.metallic   = _Metallic;
    half smooth  = _Smoothness;
    s.occlusion  = 1.0h;
#endif
    s.perceptualRoughness = 1.0h - smooth;

#if defined(_NORMALMAP)
    s.normalTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, uv), _BumpScale);
#else
    s.normalTS = half3(0, 0, 1);
#endif

#if defined(_EMISSION)
    s.emission = SAMPLE_TEXTURE2D(_EmissionMap, sampler_BaseMap, uv).rgb * _EmissionColor.rgb;
#else
    s.emission = 0;
#endif
    return s;
}
//#endregion

#endif
