// 第 12 章所有材质共用的顶点数据与顶点着色器。
// 每个材质 Shader 只需要关心“片元里怎么算 BRDF”，几何部分都一样。
#ifndef COOKBOOK_CH12_COMMON_INCLUDED
#define COOKBOOK_CH12_COMMON_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "Assets/Cookbook/Ch12/AdvBRDF.hlsl"

//#region vertex
struct Attributes
{
    float4 positionOS : POSITION;
    float3 normalOS   : NORMAL;
    float4 tangentOS  : TANGENT;
    float2 uv         : TEXCOORD0;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct Varyings
{
    float4 positionCS : SV_POSITION;
    float2 uv         : TEXCOORD0;
    float3 positionWS : TEXCOORD1;
    float3 normalWS   : TEXCOORD2;
    float4 tangentWS  : TEXCOORD3;   // w = 副切线符号（镜像 UV 时为 -1）
    float  fogFactor  : TEXCOORD4;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

Varyings Ch12Vert(Attributes input)
{
    Varyings o = (Varyings)0;
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_TRANSFER_INSTANCE_ID(input, o);
    VertexPositionInputs pos = GetVertexPositionInputs(input.positionOS.xyz);
    VertexNormalInputs nrm = GetVertexNormalInputs(input.normalOS, input.tangentOS);
    o.positionCS = pos.positionCS;
    o.positionWS = pos.positionWS;
    o.normalWS = nrm.normalWS;
    o.tangentWS = float4(nrm.tangentWS, input.tangentOS.w * GetOddNegativeScale());
    o.uv = input.uv;
    o.fogFactor = ComputeFogFactor(pos.positionCS.z);
    return o;
}

// 片元里重建正交的 T/B/N（插值后会失去正交，Gram-Schmidt 修一下）
void Ch12BuildFrame(Varyings i, out float3 T, out float3 B, out float3 N)
{
    N = normalize(i.normalWS);
    T = normalize(i.tangentWS.xyz - N * dot(i.tangentWS.xyz, N));
    B = cross(N, T) * i.tangentWS.w;
}
//#endregion

#endif
