// 第 7 章公用代码：简化光照 + ShadowCaster/DepthOnly 两个辅助 Pass。
// 本章的重点是“法线从哪来”，光照模型沿用第 5、6 章的 Lambert + 归一化 Blinn-Phong + 球谐环境光，
// 这样不同案例之间的差别只来自法线和 UV，便于对比。
#ifndef COOKBOOK_CH07_COMMON_INCLUDED
#define COOKBOOK_CH07_COMMON_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

//#region shade
// positionWS/normalWS：世界空间位置与（已经过法线贴图扰动的）法线
// gloss：0~1 映射到高光指数 2~2048；specStrength：高光强度
// extraShadow：额外的阴影系数（视差自阴影会用到），没有就传 1
half3 Ch07Shade(float3 positionWS, half3 normalWS, half3 albedo, half gloss, half specStrength, half extraShadow)
{
    float4 shadowCoord = TransformWorldToShadowCoord(positionWS);
    Light mainLight = GetMainLight(shadowCoord);

    half3 V = GetWorldSpaceNormalizeViewDir(positionWS);
    half3 L = mainLight.direction;
    half3 H = SafeNormalize(L + V);
    half NdotL = saturate(dot(normalWS, L));
    half NdotH = saturate(dot(normalWS, H));

    // URP 的灯光强度已经“乘过 π”，所以 Lambert 不再除 π，
    // 归一化 Blinn-Phong 的 (n+8)/(8π) 同理写成 (n+8)/8
    half n = exp2(gloss * 10.0 + 1.0);
    half spec = specStrength * (n + 8.0) / 8.0 * pow(NdotH, n);

    half atten = mainLight.shadowAttenuation * mainLight.distanceAttenuation * extraShadow;
    half3 direct = (albedo + spec) * NdotL * atten * mainLight.color;
    half3 ambient = SampleSH(normalWS) * albedo;     // 环境光：球谐（第 8 章细讲）
    return direct + ambient;
}
//#endregion

//#region passes
// ShadowCaster 与 DepthOnly：只依赖顶点位置和法线，与表面着色无关。
// _LightDirection/_LightPosition 由 URP 在渲染阴影时设置（见 ShadowUtils.SetupShadowCasterConstantBuffer）
float3 _LightDirection;
float3 _LightPosition;

struct Ch07ShadowAttributes
{
    float4 positionOS : POSITION;
    float3 normalOS   : NORMAL;
};

float4 Ch07ShadowVert(Ch07ShadowAttributes input) : SV_POSITION
{
    float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
    float3 normalWS = TransformObjectToWorldNormal(input.normalOS);
#if _CASTING_PUNCTUAL_LIGHT_SHADOW
    float3 lightDirectionWS = normalize(_LightPosition - positionWS);
#else
    float3 lightDirectionWS = _LightDirection;
#endif
    float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS));
#if UNITY_REVERSED_Z
    positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
#else
    positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
#endif
    return positionCS;
}

float4 Ch07DepthVert(Ch07ShadowAttributes input) : SV_POSITION
{
    return TransformObjectToHClip(input.positionOS.xyz);
}

half4 Ch07NullFrag() : SV_Target
{
    return 0;
}
//#endregion

#endif
