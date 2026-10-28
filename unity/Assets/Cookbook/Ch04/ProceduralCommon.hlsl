// 第 4 章所有“图案 Shader”共用的顶点部分：只需要位置和 UV。
#ifndef COOKBOOK_CH04_PROCEDURAL_COMMON_INCLUDED
#define COOKBOOK_CH04_PROCEDURAL_COMMON_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Assets/Cookbook/Ch04/ProceduralLib.hlsl"

struct Attributes
{
    float4 positionOS : POSITION;
    float2 uv         : TEXCOORD0;
};

struct Varyings
{
    float4 positionCS : SV_POSITION;
    float2 uv         : TEXCOORD0;
};

Varyings ProceduralVert(Attributes input)
{
    Varyings output;
    output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
    output.uv = input.uv;
    return output;
}

#endif
