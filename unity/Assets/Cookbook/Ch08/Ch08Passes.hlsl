// 第 8 章公用的辅助 Pass：ShadowCaster / DepthOnly / DepthNormals。
// 只依赖顶点位置和法线（不做 Alpha Clip），各 Shader 在 HLSLINCLUDE 里定义好 UnityPerMaterial 后再引用本文件。
#ifndef COOKBOOK_CH08_PASSES_INCLUDED
#define COOKBOOK_CH08_PASSES_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"   // Shadows.hlsl 用到 LerpWhiteTo
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

float3 _LightDirection;
float3 _LightPosition;

struct Ch08PassAttributes
{
    float4 positionOS : POSITION;
    float3 normalOS   : NORMAL;
};

struct Ch08NormalVaryings
{
    float4 positionCS : SV_POSITION;
    float3 normalWS   : TEXCOORD0;
};

float4 Ch08ShadowVert(Ch08PassAttributes input) : SV_POSITION
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

float4 Ch08DepthVert(Ch08PassAttributes input) : SV_POSITION
{
    return TransformObjectToHClip(input.positionOS.xyz);
}

half4 Ch08NullFrag() : SV_Target
{
    return 0;
}

// DepthNormals：SSAO、屏幕空间贴花等需要 _CameraNormalsTexture，没有这个 Pass 的物体在 SSAO 里是“隐形”的
Ch08NormalVaryings Ch08DepthNormalsVert(Ch08PassAttributes input)
{
    Ch08NormalVaryings o;
    o.positionCS = TransformObjectToHClip(input.positionOS.xyz);
    o.normalWS = TransformObjectToWorldNormal(input.normalOS);
    return o;
}

half4 Ch08DepthNormalsFrag(Ch08NormalVaryings input) : SV_Target
{
    return half4(NormalizeNormalPerPixel(input.normalWS), 0.0);
}

#endif
