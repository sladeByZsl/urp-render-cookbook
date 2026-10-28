// 第 16 章共用：顶点结构 + 一个简单的 Lambert/Blinn-Phong 光照（带主光阴影和环境光）。
// 这一章的重点是渲染状态（Blend/ZWrite/ZTest/Cull/Stencil），光照尽量简单。
#ifndef COOKBOOK_CH16_COMMON_INCLUDED
#define COOKBOOK_CH16_COMMON_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

struct Attributes
{
    float4 positionOS : POSITION;
    float3 normalOS   : NORMAL;
    float2 uv         : TEXCOORD0;
};

struct Varyings
{
    float4 positionCS : SV_POSITION;
    float2 uv         : TEXCOORD0;
    float3 positionWS : TEXCOORD1;
    float3 normalWS   : TEXCOORD2;
};

Varyings Ch16Vert(Attributes v)
{
    Varyings o;
    o.positionWS = TransformObjectToWorld(v.positionOS.xyz);
    o.positionCS = TransformWorldToHClip(o.positionWS);
    o.normalWS   = TransformObjectToWorldNormal(v.normalOS);
    o.uv         = v.uv;
    return o;
}

half3 SimpleLighting(half3 albedo, float3 N, float3 positionWS, half specular)
{
    Light L = GetMainLight(TransformWorldToShadowCoord(positionWS));
    float3 V = GetWorldSpaceNormalizeViewDir(positionWS);
    float3 H = normalize(L.direction + V);
    half atten = L.shadowAttenuation;
    half3 diffuse = albedo * (saturate(dot(N, L.direction)) * atten * L.color + SampleSH(N));
    half3 spec = pow(saturate(dot(N, H)), 64.0h) * specular * atten * L.color;
    return diffuse + spec;
}

// ShadowCaster 用
float3 _LightDirection;
float4 Ch16ShadowPositionCS(float3 positionOS, float3 normalOS)
{
    float3 positionWS = TransformObjectToWorld(positionOS);
    float3 normalWS = TransformObjectToWorldNormal(normalOS);
    float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, _LightDirection));
#if UNITY_REVERSED_Z
    positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
#else
    positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
#endif
    return positionCS;
}

#endif
