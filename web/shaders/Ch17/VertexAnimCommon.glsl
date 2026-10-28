// 第 17 章顶点动画的公共部分：输入结构 + 光照 + 三个 Pass 的顶点函数。（GLSL 版，对应 Ch17/VertexAnimCommon.hlsl）
//
// 用法（写在 Shader 的 GLSLINCLUDE 里）：
//   1. 声明材质属性的 uniform
//   2. #include 本文件 "Ch17/VertexAnimCommon.glsl"（只有结构体和工具函数）
//   3. 实现 void Deform(inout VAAttributes v)：在物体空间里改 positionOS / normalOS
//   4. #include "Ch17/VertexAnimPasses.glsl"：ForwardLit / ShadowCaster / DepthOnly 的顶点函数都会调用 Deform
// 这样“同一个变形”被所有 Pass 共用，阴影和深度天然与画面一致。
#ifndef COOKBOOK_CH17_VA_COMMON_INCLUDED
#define COOKBOOK_CH17_VA_COMMON_INCLUDED

//#region attributes
// GLSL 的顶点输入是固定名字的全局变量（positionOS、normalOS、color、texcoord0..3），
// 这里把它们装进一个结构体，Deform 才能像 HLSL 版一样 inout 修改
struct VAAttributes
{
    vec4 positionOS;
    vec3 normalOS;
    vec4 color;       // 草：R = 高度权重，G = 随机数
    vec2 uv;
    vec4 uv1;         // 草：根部位置；碎裂：三角形中心 + 随机数；VAT：顶点编号
    vec4 uv2;         // 碎裂：面法线；也可在 Deform 里写入，传给片元（extra）
};
//#endregion

// Varyings（WebGL 不允许结构体做 varying；color 和顶点输入重名，改叫 vertColor）
VARYING vec2 uv;
VARYING vec3 positionWS;
VARYING vec3 normalWS;
VARYING vec4 vertColor;
VARYING vec4 extra;     // Deform 写进 uv2 的数据，原样交给片元

#ifdef VERTEX
VAAttributes VAGetAttributes()
{
    VAAttributes v;
    v.positionOS = positionOS;
    v.normalOS = normalOS;
    v.color = color;
    v.uv = texcoord0.xy;
    v.uv1 = texcoord1;
    v.uv2 = texcoord2;
    return v;
}
#endif

// 简单的 Lambert + Blinn-Phong + 球谐环境光 + 主光阴影
vec3 VALighting(vec3 albedo, vec3 N, vec3 positionWS, float specular, float gloss)
{
    Light L = GetMainLight(TransformWorldToShadowCoord(positionWS));
    vec3 V = GetWorldSpaceNormalizeViewDir(positionWS);
    vec3 H = normalize(L.direction + V);
    float atten = L.shadowAttenuation;
    vec3 col = albedo * (saturate(dot(N, L.direction)) * atten * L.color + SampleSH(N));
    col += pow(saturate(dot(N, H)), gloss) * specular * atten * L.color;
    return col;
}

// _LightDirection：ShadowCaster 用，由引擎设置（Lighting.glsl 里已声明）

#endif
