#ifndef COOKBOOK_CH10_MINIMAL_LIT_INPUT_INCLUDED
#define COOKBOOK_CH10_MINIMAL_LIT_INPUT_INCLUDED

// “最小 Lit”的材质输入。（GLSL 版，对应 Ch10/MinimalLitInput.hlsl）
// 三个 Pass（ForwardLit / ShadowCaster / DepthOnly）共用这一份，
// 保证 UnityPerMaterial 布局完全一致 —— 这是 SRP Batcher 兼容的前提。
// HLSL 版 include 了 SurfaceInput.hlsl（声明 _BaseMap / _BumpMap / _EmissionMap 以及 SampleAlbedoAlpha、SampleNormal、Alpha）；
// GLSL 没有 TEXTURE2D_ARGS 这种“贴图 + 采样器”参数宏，下面直接写出这几个函数，采样固定的那张贴图。

//#region cbuffer
uniform vec4  _BaseMap_ST;
uniform vec4  _BaseColor;
uniform vec4  _EmissionColor;
uniform float _Cutoff;        // ShadowCasterPass / DepthOnlyPass 在 _ALPHATEST_ON 时会用到
uniform float _Metallic;
uniform float _Smoothness;
uniform float _BumpScale;
//#endregion

// ---- SurfaceInput.hlsl ----
uniform sampler2D _BaseMap;
uniform sampler2D _BumpMap;
uniform sampler2D _EmissionMap;

vec4 SampleAlbedoAlpha(vec2 uv) { return texture(_BaseMap, uv); }

float Alpha(float albedoAlpha, vec4 color, float cutoff)
{
    float alpha = albedoAlpha * color.a;
#ifdef _ALPHATEST_ON
    if (alpha - cutoff < 0.0) discard;
#endif
    return alpha;
}

vec3 SampleNormal(vec2 uv, float scale)
{
#ifdef _NORMALMAP
    return UnpackNormalScale(texture(_BumpMap, uv), scale);
#else
    return vec3(0.0, 0.0, 1.0);
#endif
}

#endif
