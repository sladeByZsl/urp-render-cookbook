// 第 15 章各个风格化 Shader 共用的顶点结构、主光获取，以及 ShadowCaster / DepthOnly 的通用实现。（GLSL 版，对应 Ch15/NPRCommon.hlsl）
// 用法：Shader 先声明自己的 uniform（对应 CBUFFER(UnityPerMaterial)），再 #include 本文件。
// GLSL 版额外约定：着色 Pass 先 #define NPR_VARYINGS 再 include，得到 NprVaryings 对应的 varying 变量和 NprVert()；
// 投影/深度 Pass 先 #define NPR_SHADOW_PASS 或 NPR_DEPTH_PASS，直接得到整个 Pass 的 main()。
#ifndef COOKBOOK_CH15_NPR_COMMON_INCLUDED
#define COOKBOOK_CH15_NPR_COMMON_INCLUDED

#ifdef NPR_VARYINGS
// NprVaryings（WebGL 不允许结构体做 varying，拆成单独的变量）
VARYING vec2  uv;
VARYING vec3  positionWS;
VARYING vec3  normalWS;
VARYING vec4  vertexColor;    // 顶点输入已占用 color 这个名字
VARYING float fogFactor;

#ifdef VERTEX
void NprVert()
{
    VertexPositionInputs pos = GetVertexPositionInputs(positionOS.xyz);
    gl_Position = pos.positionCS;
    positionWS  = pos.positionWS;
    normalWS    = TransformObjectToWorldNormal(normalOS);
    uv          = texcoord0.xy;
    vertexColor = color;
    fogFactor   = ComputeFogFactor(pos.positionCS.z);
}
#endif
#endif

//#region npr-light
// 风格化着色只需要“原料”：未截断的 N·L（-1..1）、阴影衰减、光的颜色和方向。
// 怎么把它们变成颜色，交给各个 Shader 自己决定。
struct NprLight
{
    vec3  direction;
    vec3  color;
    float ndotl;      // 未 saturate，Gooch/Hatching 需要背光面的信息
    float shadow;     // 0 = 完全在阴影里，1 = 受光
};

NprLight GetNprLight(vec3 posWS, vec3 nrmWS)
{
    vec4 shadowCoord = TransformWorldToShadowCoord(posWS);  // 逐像素算，级联阴影也正确
    Light l = GetMainLight(shadowCoord);
    NprLight o;
    o.direction = l.direction;
    o.color     = l.color;
    o.ndotl     = dot(nrmWS, l.direction);
    o.shadow    = l.shadowAttenuation;
    return o;
}
//#endregion

// ---------------- ShadowCaster / DepthOnly ----------------
// _LightDirection / _LightPosition 由引擎在渲染阴影时设置（Lighting.glsl 里已声明）
#ifdef VERTEX
vec4 NprShadowVert()
{
    vec3 posWS = TransformObjectToWorld(positionOS.xyz);
    vec3 nrmWS = TransformObjectToWorldNormal(normalOS);
    // _CASTING_PUNCTUAL_LIGHT_SHADOW 关键字在 GLSL 版里是个 uniform
    vec3 lightDir = _CastingPunctualLightShadow > 0.5 ? normalize(_LightPosition - posWS) : _LightDirection;
    vec4 positionCS = TransformWorldToHClip(ApplyShadowBias(posWS, nrmWS, lightDir));
    // WebGL 深度不反转（UNITY_REVERSED_Z = 0）：把近平面之前的投影物压到近平面上
    positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE * positionCS.w);
    return positionCS;
}

vec4 NprDepthVert()
{
    return TransformObjectToHClip(positionOS.xyz);
}
#endif

#ifdef FRAGMENT
vec4 NprNullFrag() { return vec4(0.0); }
#endif

#ifdef NPR_SHADOW_PASS
#ifdef VERTEX
void main() { gl_Position = NprShadowVert(); }
#endif
#ifdef FRAGMENT
void main() { fragColor = NprNullFrag(); }
#endif
#endif

#ifdef NPR_DEPTH_PASS
#ifdef VERTEX
void main() { gl_Position = NprDepthVert(); }
#endif
#ifdef FRAGMENT
void main() { fragColor = vec4(gl_FragCoord.z); }   // 与 URP DepthOnlyPass 一致：深度写进 R 通道
#endif
#endif

#endif
