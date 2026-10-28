// 第 15 章各个风格化 Shader 共用的顶点结构、主光获取，以及 ShadowCaster / DepthOnly 的通用实现。
// 用法：Shader 先声明自己的 CBUFFER(UnityPerMaterial)，再 #include 本文件。
#ifndef COOKBOOK_CH15_NPR_COMMON_INCLUDED
#define COOKBOOK_CH15_NPR_COMMON_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

struct NprAttributes
{
    float4 positionOS : POSITION;
    float3 normalOS   : NORMAL;
    float2 uv         : TEXCOORD0;
    float4 color      : COLOR;
};

struct NprVaryings
{
    float4 positionCS : SV_POSITION;
    float2 uv         : TEXCOORD0;
    float3 positionWS : TEXCOORD1;
    float3 normalWS   : TEXCOORD2;
    float4 color      : TEXCOORD3;
    float  fogFactor  : TEXCOORD4;
};

NprVaryings NprVert(NprAttributes v)
{
    NprVaryings o;
    VertexPositionInputs pos = GetVertexPositionInputs(v.positionOS.xyz);
    o.positionCS = pos.positionCS;
    o.positionWS = pos.positionWS;
    o.normalWS   = TransformObjectToWorldNormal(v.normalOS);
    o.uv         = v.uv;
    o.color      = v.color;
    o.fogFactor  = ComputeFogFactor(pos.positionCS.z);
    return o;
}

//#region npr-light
// 风格化着色只需要“原料”：未截断的 N·L（-1..1）、阴影衰减、光的颜色和方向。
// 怎么把它们变成颜色，交给各个 Shader 自己决定。
struct NprLight
{
    float3 direction;
    float3 color;
    float  ndotl;      // 未 saturate，Gooch/Hatching 需要背光面的信息
    float  shadow;     // 0 = 完全在阴影里，1 = 受光
};

NprLight GetNprLight(float3 positionWS, float3 normalWS)
{
    float4 shadowCoord = TransformWorldToShadowCoord(positionWS);  // 逐像素算，级联阴影也正确
    Light l = GetMainLight(shadowCoord);
    NprLight o;
    o.direction = l.direction;
    o.color     = l.color;
    o.ndotl     = dot(normalWS, l.direction);
    o.shadow    = l.shadowAttenuation;
    return o;
}
//#endregion

// ---------------- ShadowCaster / DepthOnly ----------------
float3 _LightDirection;   // 由 URP 的 ShadowUtils 在渲染阴影时设置
float3 _LightPosition;

struct NprShadowAttributes
{
    float4 positionOS : POSITION;
    float3 normalOS   : NORMAL;
};

float4 NprShadowVert(NprShadowAttributes v) : SV_POSITION
{
    float3 positionWS = TransformObjectToWorld(v.positionOS.xyz);
    float3 normalWS   = TransformObjectToWorldNormal(v.normalOS);
#if _CASTING_PUNCTUAL_LIGHT_SHADOW
    float3 lightDir = normalize(_LightPosition - positionWS);
#else
    float3 lightDir = _LightDirection;
#endif
    float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDir));
#if UNITY_REVERSED_Z
    positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
#else
    positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
#endif
    return positionCS;
}

float4 NprDepthVert(NprShadowAttributes v) : SV_POSITION
{
    return TransformObjectToHClip(v.positionOS.xyz);
}

half4 NprNullFrag() : SV_Target { return 0; }

#endif
