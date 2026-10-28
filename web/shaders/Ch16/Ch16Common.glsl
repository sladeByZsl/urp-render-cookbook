// 第 16 章共用：顶点结构 + 一个简单的 Lambert/Blinn-Phong 光照（带主光阴影和环境光）。（GLSL 版，对应 Ch16/Ch16Common.hlsl）
// 这一章的重点是渲染状态（Blend/ZWrite/ZTest/Cull/Stencil），光照尽量简单。
#ifndef COOKBOOK_CH16_COMMON_INCLUDED
#define COOKBOOK_CH16_COMMON_INCLUDED

// Varyings：WebGL 不允许结构体做 varying，拆成单独的变量
VARYING vec2 uv;
VARYING vec3 positionWS;
VARYING vec3 normalWS;

#ifdef VERTEX
void Ch16Vert()
{
    positionWS  = TransformObjectToWorld(positionOS.xyz);
    gl_Position = TransformWorldToHClip(positionWS);
    normalWS    = TransformObjectToWorldNormal(normalOS);
    uv          = texcoord0.xy;
}
#endif

vec3 SimpleLighting(vec3 albedo, vec3 N, vec3 positionWS, float specular)
{
    Light L = GetMainLight(TransformWorldToShadowCoord(positionWS));
    vec3 V = GetWorldSpaceNormalizeViewDir(positionWS);
    vec3 H = normalize(L.direction + V);
    float atten = L.shadowAttenuation;
    vec3 diffuse = albedo * (saturate(dot(N, L.direction)) * atten * L.color + SampleSH(N));
    vec3 spec = pow(saturate(dot(N, H)), 64.0) * specular * atten * L.color;
    return diffuse + spec;
}

// ShadowCaster 用（_LightDirection 由引擎设置，Lighting.glsl 里已声明）
vec4 Ch16ShadowPositionCS(vec3 positionOS, vec3 normalOS)
{
    vec3 positionWS = TransformObjectToWorld(positionOS);
    vec3 normalWS = TransformObjectToWorldNormal(normalOS);
    vec4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, _LightDirection));
#if UNITY_REVERSED_Z
    positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
#else
    positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE * positionCS.w);
#endif
    return positionCS;
}

#endif
