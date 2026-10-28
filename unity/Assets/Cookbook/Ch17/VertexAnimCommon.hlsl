// 第 17 章顶点动画的公共部分：输入结构 + 光照 + 三个 Pass 的顶点函数。
//
// 用法（写在 Shader 的 HLSLINCLUDE 里）：
//   1. #include Core.hlsl，声明 CBUFFER(UnityPerMaterial)
//   2. #include 本文件的 "VertexAnimCommon.hlsl"（只有结构体和工具函数）
//   3. 实现 void Deform(inout VAAttributes v)：在物体空间里改 positionOS / normalOS
//   4. #include "VertexAnimPasses.hlsl"：ForwardLit / ShadowCaster / DepthOnly 的顶点函数都会调用 Deform
// 这样“同一个变形”被所有 Pass 共用，阴影和深度天然与画面一致。
#ifndef COOKBOOK_CH17_VA_COMMON_INCLUDED
#define COOKBOOK_CH17_VA_COMMON_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

//#region attributes
struct VAAttributes
{
    float4 positionOS : POSITION;
    float3 normalOS   : NORMAL;
    float4 color      : COLOR;       // 草：R = 高度权重，G = 随机数
    float2 uv         : TEXCOORD0;
    float4 uv1        : TEXCOORD1;   // 草：根部位置；碎裂：三角形中心 + 随机数；VAT：顶点编号
    float4 uv2        : TEXCOORD2;   // 碎裂：面法线；也可在 Deform 里写入，传给片元（extra）
};
//#endregion

struct VAVaryings
{
    float4 positionCS : SV_POSITION;
    float2 uv         : TEXCOORD0;
    float3 positionWS : TEXCOORD1;
    float3 normalWS   : TEXCOORD2;
    float4 color      : TEXCOORD3;
    float4 extra      : TEXCOORD4;   // Deform 写进 uv2 的数据，原样交给片元
};

// 简单的 Lambert + Blinn-Phong + 球谐环境光 + 主光阴影
half3 VALighting(half3 albedo, float3 N, float3 positionWS, half specular, half gloss)
{
    Light L = GetMainLight(TransformWorldToShadowCoord(positionWS));
    float3 V = GetWorldSpaceNormalizeViewDir(positionWS);
    float3 H = normalize(L.direction + V);
    half atten = L.shadowAttenuation;
    half3 col = albedo * (saturate(dot(N, L.direction)) * atten * L.color + SampleSH(N));
    col += pow(saturate(dot(N, H)), gloss) * specular * atten * L.color;
    return col;
}

float3 _LightDirection;   // ShadowCaster 用，由 URP 设置

#endif
