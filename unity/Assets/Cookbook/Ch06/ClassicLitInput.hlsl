// 案例 6.9 ClassicLit 的材质输入：所有 Pass 共享同一个 UnityPerMaterial，保证 SRP Batcher 兼容
#ifndef COOKBOOK_CH06_CLASSIC_LIT_INPUT_INCLUDED
#define COOKBOOK_CH06_CLASSIC_LIT_INPUT_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

CBUFFER_START(UnityPerMaterial)
    float4 _BaseMap_ST;
    half4  _BaseColor;
    half4  _SpecColor;
    half   _Smoothness;
    half4  _EmissionColor;
    half   _Cutoff;
CBUFFER_END

TEXTURE2D(_BaseMap);
SAMPLER(sampler_BaseMap);

#endif
