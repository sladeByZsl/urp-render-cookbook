// 案例 6.4 手写 ShadowCaster Pass：把物体画进光源的阴影图（只写深度）。
// 用法：在 Pass 里先声明好材质 CBUFFER（需要 Alpha 裁剪时要有 _BaseMap/_BaseColor/_Cutoff），再 include 本文件。
#ifndef COOKBOOK_CH06_SHADOW_CASTER_PASS_INCLUDED
#define COOKBOOK_CH06_SHADOW_CASTER_PASS_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
// Shadows.hlsl 里的 SampleShadowmap 用到 LerpWhiteTo()，它在 CommonMaterial.hlsl 里，必须先 include
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

//#region lightparams
// 由 URP 的 MainLightShadowCasterPass / AdditionalLightsShadowCasterPass 在画每个阴影切片前设置
// （见 Runtime/ShadowUtils.cs 的 SetupShadowCasterConstantBuffer）
float3 _LightDirection;   // 方向光：指向光源的方向
float3 _LightPosition;    // 点光 / 聚光：光源的世界坐标
//#endregion

struct ShadowCasterAttributes
{
    float4 positionOS : POSITION;
    float3 normalOS   : NORMAL;
    float2 texcoord   : TEXCOORD0;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct ShadowCasterVaryings
{
#if defined(_ALPHATEST_ON)
    float2 uv         : TEXCOORD0;
#endif
    float4 positionCS : SV_POSITION;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

//#region shadowpos
float4 GetShadowCasterPositionCS(float3 positionWS, float3 normalWS)
{
    // 1) 求“指向光源”的方向：方向光处处相同；点光/聚光每个顶点不同
#if defined(_CASTING_PUNCTUAL_LIGHT_SHADOW)
    float3 lightDirectionWS = normalize(_LightPosition - positionWS);
#else
    float3 lightDirectionWS = _LightDirection;
#endif

    // 2) 在世界空间里做深度偏移 + 法线偏移，再变换到光源的裁剪空间
    //    （此刻 UNITY_MATRIX_VP 已被 URP 设成了“光源相机”的 VP 矩阵）
    float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS));

    // 3) 把跑到近平面之外的顶点“压扁”到近平面上（Shadow Pancaking），
    //    否则光源近平面之前的投射体会被裁掉，阴影凭空缺一块
#if UNITY_REVERSED_Z
    positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
#else
    positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
#endif
    return positionCS;
}
//#endregion

ShadowCasterVaryings ShadowCasterVertex(ShadowCasterAttributes input)
{
    ShadowCasterVaryings output = (ShadowCasterVaryings)0;
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_TRANSFER_INSTANCE_ID(input, output);

    float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
    float3 normalWS = TransformObjectToWorldNormal(input.normalOS);
    output.positionCS = GetShadowCasterPositionCS(positionWS, normalWS);
#if defined(_ALPHATEST_ON)
    output.uv = TRANSFORM_TEX(input.texcoord, _BaseMap);
#endif
    return output;
}

half4 ShadowCasterFragment(ShadowCasterVaryings input) : SV_Target
{
    UNITY_SETUP_INSTANCE_ID(input);
#if defined(_ALPHATEST_ON)
    // 镂空材质的影子也要镂空：和颜色 Pass 用同样的 clip
    half alpha = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv).a * _BaseColor.a;
    clip(alpha - _Cutoff);
#endif
    return 0;
}

#endif
