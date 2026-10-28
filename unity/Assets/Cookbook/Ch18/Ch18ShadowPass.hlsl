// 本章不透明 Shader 共用的 ShadowCaster / DepthOnly 顶点与片元函数（无顶点动画、无裁剪）。
// 用法：在 SubShader 的 HLSLINCLUDE 里声明好 UnityPerMaterial，各 Pass 再 include 本文件。
// 这样所有 Pass 的 CBUFFER 完全一致，SRP Batcher 兼容；而 UsePass 借用 Lit 的 Pass 会带来
// 另一套 UnityPerMaterial，导致材质不兼容 SRP Batcher。
#ifndef COOKBOOK_CH18_SHADOW_PASS_INCLUDED
#define COOKBOOK_CH18_SHADOW_PASS_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
// Shadows.hlsl 用到 CommonMaterial.hlsl 里的 LerpWhiteTo，URP 的 Lit 是经由 LitInput 间接包含的
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

float3 _LightDirection;
float3 _LightPosition;

struct ShadowAttributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; };
struct ShadowVaryings  { float4 positionCS : SV_POSITION; };

ShadowVaryings ShadowVert(ShadowAttributes v)
{
    ShadowVaryings o;
    float3 positionWS = TransformObjectToWorld(v.positionOS.xyz);
    float3 normalWS = TransformObjectToWorldNormal(v.normalOS);
#if _CASTING_PUNCTUAL_LIGHT_SHADOW
    float3 lightDirWS = normalize(_LightPosition - positionWS);
#else
    float3 lightDirWS = _LightDirection;
#endif
    o.positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirWS));
#if UNITY_REVERSED_Z
    o.positionCS.z = min(o.positionCS.z, UNITY_NEAR_CLIP_VALUE);
#else
    o.positionCS.z = max(o.positionCS.z, UNITY_NEAR_CLIP_VALUE);
#endif
    return o;
}

half4 ShadowFrag(ShadowVaryings i) : SV_Target { return 0; }

ShadowVaryings DepthVert(ShadowAttributes v)
{
    ShadowVaryings o;
    o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
    return o;
}

half4 DepthFrag(ShadowVaryings i) : SV_Target { return i.positionCS.z; }

#endif
