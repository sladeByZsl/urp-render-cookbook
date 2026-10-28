#ifndef COOKBOOK_CH10_MINIMAL_LIT_INPUT_INCLUDED
#define COOKBOOK_CH10_MINIMAL_LIT_INPUT_INCLUDED

// “最小 Lit”的材质输入。三个 Pass（ForwardLit / ShadowCaster / DepthOnly）共用这一份，
// 保证 UnityPerMaterial 布局完全一致 —— 这是 SRP Batcher 兼容的前提。
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
// SurfaceInput.hlsl 声明了 _BaseMap / _BumpMap / _EmissionMap 以及 SampleAlbedoAlpha、SampleNormal、Alpha 等辅助函数，
// URP 的 ShadowCasterPass.hlsl、DepthOnlyPass.hlsl 也依赖这些名字。
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/SurfaceInput.hlsl"

//#region cbuffer
CBUFFER_START(UnityPerMaterial)
    float4 _BaseMap_ST;
    half4  _BaseColor;
    half4  _EmissionColor;
    half   _Cutoff;        // ShadowCasterPass / DepthOnlyPass 在 _ALPHATEST_ON 时会用到
    half   _Metallic;
    half   _Smoothness;
    half   _BumpScale;
CBUFFER_END
//#endregion

#endif
