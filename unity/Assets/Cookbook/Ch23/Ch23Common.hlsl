// 第 23 章共用：一个最小的 ShadowCaster / DepthOnly 实现。
// 写法与 URP 14 的 Shaders/ShadowCasterPass.hlsl 一致，只是去掉了 Alpha 裁剪和 LOD 交叉淡化，
// 让本章的各个 Shader 不必依赖 LitInput.hlsl 的材质变量。
#ifndef COOKBOOK_CH23_COMMON_INCLUDED
#define COOKBOOK_CH23_COMMON_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
// Shadows.hlsl 用到 LerpWhiteTo（定义在 CommonMaterial.hlsl），Lit 是通过 SurfaceInput.hlsl 间接带进来的
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

// 由 ShadowUtils.SetupShadowCasterConstantBuffer 每盏灯设置一次
float3 _LightDirection;
float3 _LightPosition;

struct CasterAttributes
{
    float4 positionOS : POSITION;
    float3 normalOS   : NORMAL;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

//#region caster
float4 Ch23ShadowCasterVert(CasterAttributes input) : SV_POSITION
{
    UNITY_SETUP_INSTANCE_ID(input);
    float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
    float3 normalWS   = TransformObjectToWorldNormal(input.normalOS);

#if _CASTING_PUNCTUAL_LIGHT_SHADOW
    float3 lightDirectionWS = normalize(_LightPosition - positionWS);
#else
    float3 lightDirectionWS = _LightDirection;
#endif
    // Depth Bias 沿光线方向推远、Normal Bias 沿法线向内收缩，都在投射端完成
    float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS));

    // 把超出近裁剪面的投射体压到近平面上（Pancaking），避免它们被裁掉后漏光
#if UNITY_REVERSED_Z
    positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
#else
    positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
#endif
    return positionCS;
}
//#endregion

float4 Ch23DepthOnlyVert(CasterAttributes input) : SV_POSITION
{
    UNITY_SETUP_INSTANCE_ID(input);
    return TransformObjectToHClip(input.positionOS.xyz);
}

half4 Ch23NullFrag() : SV_Target { return 0; }

#endif
