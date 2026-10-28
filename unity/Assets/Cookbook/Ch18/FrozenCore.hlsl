// 冰冻覆盖的公共部分：材质参数、三平面噪声、覆盖遮罩、顶点加厚。Forward/Shadow/Depth 三个 Pass 共用。
#ifndef COOKBOOK_CH18_FROZEN_CORE_INCLUDED
#define COOKBOOK_CH18_FROZEN_CORE_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

TEXTURE2D(_BaseMap);  SAMPLER(sampler_BaseMap);
TEXTURE2D(_IceNoise); SAMPLER(sampler_IceNoise);
TEXTURE2D(_CrackMap); SAMPLER(sampler_CrackMap);

CBUFFER_START(UnityPerMaterial)
    float4 _BaseMap_ST;
    half4  _BaseColor;
    half   _Smoothness;
    half   _Freeze;
    half4  _IceColor;
    half4  _IceDeepColor;
    float  _IceNoiseScale;
    float  _CrackScale;
    half   _CrackStrength;
    half   _Thickness;
    half4  _IceRimColor;
    half   _SparkleStrength;
CBUFFER_END

//#region triplanar
// 极简三平面采样：按法线三个分量的权重，混合 YZ / XZ / XY 三个方向的投影
half TriplanarNoise(TEXTURE2D_PARAM(tex, samp), float3 positionWS, half3 normalWS, float scale)
{
    half3 w = pow(abs(normalWS), 4.0h);
    w /= (w.x + w.y + w.z);
    half x = SAMPLE_TEXTURE2D_LOD(tex, samp, positionWS.zy * scale, 0).r;
    half y = SAMPLE_TEXTURE2D_LOD(tex, samp, positionWS.xz * scale, 0).r;
    half z = SAMPLE_TEXTURE2D_LOD(tex, samp, positionWS.xy * scale, 0).r;
    return x * w.x + y * w.y + z * w.z;
}
//#endregion

//#region mask
// 覆盖遮罩：法线越朝上越先结冰，噪声把分界线打散。_Freeze 0→1，阈值从“只有正上方”一路降到“全覆盖”
half FrostMask(float3 positionWS, half3 normalWS)
{
    half n = TriplanarNoise(TEXTURE2D_ARGS(_IceNoise, sampler_IceNoise), positionWS, normalWS, _IceNoiseScale);
    half up = normalWS.y + (n - 0.5h) * 0.8h;          // -1.4 ~ 1.4
    half threshold = lerp(1.5h, -1.5h, _Freeze);
    return smoothstep(threshold - 0.1h, threshold + 0.1h, up);
}
//#endregion

//#region thicken
// 冰层有厚度：被覆盖的顶点沿法线外推。阴影和深度 Pass 也要做同样的外推，否则阴影对不上
float3 ThickenIce(float3 positionWS, half3 normalWS)
{
    return positionWS + normalWS * FrostMask(positionWS, normalWS) * _Thickness;
}
//#endregion

#endif
