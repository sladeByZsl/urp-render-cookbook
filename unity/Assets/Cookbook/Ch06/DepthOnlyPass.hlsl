// DepthOnly Pass：只写深度。URP 做深度预渲染（Depth Prepass）、生成 _CameraDepthTexture 时会用到它。
#ifndef COOKBOOK_CH06_DEPTH_ONLY_PASS_INCLUDED
#define COOKBOOK_CH06_DEPTH_ONLY_PASS_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

struct DepthOnlyAttributes
{
    float4 positionOS : POSITION;
    float2 texcoord   : TEXCOORD0;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct DepthOnlyVaryings
{
#if defined(_ALPHATEST_ON)
    float2 uv         : TEXCOORD0;
#endif
    float4 positionCS : SV_POSITION;
    UNITY_VERTEX_INPUT_INSTANCE_ID
    UNITY_VERTEX_OUTPUT_STEREO
};

DepthOnlyVaryings DepthOnlyVertex(DepthOnlyAttributes input)
{
    DepthOnlyVaryings output = (DepthOnlyVaryings)0;
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_TRANSFER_INSTANCE_ID(input, output);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);
    output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
#if defined(_ALPHATEST_ON)
    output.uv = TRANSFORM_TEX(input.texcoord, _BaseMap);
#endif
    return output;
}

half DepthOnlyFragment(DepthOnlyVaryings input) : SV_Target
{
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
#if defined(_ALPHATEST_ON)
    clip(SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv).a * _BaseColor.a - _Cutoff);
#endif
    // 深度由硬件写入；某些路径会把深度作为颜色写进 R 通道（Pass 里 ColorMask R），所以照 URP 的做法返回 z
    return input.positionCS.z;
}

#endif
