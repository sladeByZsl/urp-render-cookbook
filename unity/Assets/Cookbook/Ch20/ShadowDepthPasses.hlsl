// 第 20 章地形 Shader 共用的 ShadowCaster / DepthOnly / DepthNormals 顶点与片元函数（无顶点变形、无 Alpha 裁剪）
// 使用方：先定义好自己的 UnityPerMaterial CBUFFER，再 include 本文件。
#ifndef COOKBOOK_CH20_SHADOW_DEPTH_INCLUDED
#define COOKBOOK_CH20_SHADOW_DEPTH_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"   // Shadows.hlsl 用到其中的 LerpWhiteTo
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

float3 _LightDirection;
float3 _LightPosition;

struct ShadowDepthAttributes
{
    float4 positionOS : POSITION;
    float3 normalOS   : NORMAL;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct ShadowDepthVaryings
{
    float4 positionCS : SV_POSITION;
    half3 normalWS    : TEXCOORD0;
};

ShadowDepthVaryings Ch20ShadowVert(ShadowDepthAttributes input)
{
    ShadowDepthVaryings o = (ShadowDepthVaryings)0;
    UNITY_SETUP_INSTANCE_ID(input);
    float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
    float3 normalWS = TransformObjectToWorldNormal(input.normalOS);
#if _CASTING_PUNCTUAL_LIGHT_SHADOW
    float3 lightDirectionWS = normalize(_LightPosition - positionWS);
#else
    float3 lightDirectionWS = _LightDirection;
#endif
    o.positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS));
#if UNITY_REVERSED_Z
    o.positionCS.z = min(o.positionCS.z, UNITY_NEAR_CLIP_VALUE);
#else
    o.positionCS.z = max(o.positionCS.z, UNITY_NEAR_CLIP_VALUE);
#endif
    return o;
}

ShadowDepthVaryings Ch20DepthVert(ShadowDepthAttributes input)
{
    ShadowDepthVaryings o = (ShadowDepthVaryings)0;
    UNITY_SETUP_INSTANCE_ID(input);
    o.positionCS = TransformObjectToHClip(input.positionOS.xyz);
    o.normalWS = TransformObjectToWorldNormal(input.normalOS);
    return o;
}

half4 Ch20EmptyFrag(ShadowDepthVaryings input) : SV_Target
{
    return 0;
}

half4 Ch20DepthNormalsFrag(ShadowDepthVaryings input) : SV_Target
{
    // URP 14 的 _CameraNormalsTexture 存的是归一化的世界空间法线
    return half4(NormalizeNormalPerPixel(input.normalWS), 0.0);
}

#endif
