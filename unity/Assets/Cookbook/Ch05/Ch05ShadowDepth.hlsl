// 第 5 章所有 Shader 共用的 ShadowCaster / DepthOnly 顶点与片元函数。
// 本章只关心“表面怎么被照亮”，这两个 Pass 只负责让物体能投影、能写进深度图，
// 它们的原理（ApplyShadowBias、_CASTING_PUNCTUAL_LIGHT_SHADOW 等）在第 6 章细讲。
#ifndef COOKBOOK_CH05_SHADOW_DEPTH_INCLUDED
#define COOKBOOK_CH05_SHADOW_DEPTH_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
// Shadows.hlsl 用到了 LerpWhiteTo()，它定义在 CommonMaterial.hlsl 里，但 Shadows.hlsl 自己没有 include。
// URP 自带的 Lit 之所以不报错，是因为 LitInput.hlsl 先 include 了它。自己写 ShadowCaster 时要补上。
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

// 由 URP 的阴影 Pass 在绘制每个投射光源前设置
float3 _LightDirection;
float3 _LightPosition;

struct ShadowDepthAttributes
{
    float4 positionOS : POSITION;
    float3 normalOS   : NORMAL;
};

float4 ShadowDepthVert(ShadowDepthAttributes input) : SV_POSITION
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

half4 ShadowDepthFrag(float4 positionCS : SV_POSITION) : SV_Target
{
    return 0;   // ColorMask 0，只写深度
}

float4 DepthOnlyVert(ShadowDepthAttributes input) : SV_POSITION
{
    return TransformObjectToHClip(input.positionOS.xyz);
}

half DepthOnlyFrag(float4 positionCS : SV_POSITION) : SV_Target
{
    return positionCS.z;   // 与 URP DepthOnlyPass.hlsl 一致：某些路径把深度写进 R 通道
}

#endif
