// 第 12 章所有材质共用的顶点数据与顶点着色器（GLSL 版，对应 Ch12Common.hlsl）。
// 每个材质 Shader 只需要关心“片元里怎么算 BRDF”，几何部分都一样。
// GLSL 版说明：Core.glsl / Lighting.glsl 自动包含；WebGL 不允许结构体做 varying，Varyings 拆成单独的 VARYING 变量。
#ifndef COOKBOOK_CH12_COMMON_INCLUDED
#define COOKBOOK_CH12_COMMON_INCLUDED

#include "Ch12/AdvBRDF.glsl"

//#region vertex
VARYING vec2  uv;
VARYING vec3  positionWS;
VARYING vec3  normalWS;
VARYING vec4  tangentWS;   // w = 副切线符号（镜像 UV 时为 -1）
VARYING float fogFactor;

#ifdef VERTEX
void Ch12Vert()
{
    VertexPositionInputs pos = GetVertexPositionInputs(positionOS.xyz);
    VertexNormalInputs nrm = GetVertexNormalInputs(normalOS, tangentOS);
    gl_Position = pos.positionCS;
    positionWS = pos.positionWS;
    normalWS = nrm.normalWS;
    tangentWS = vec4(nrm.tangentWS, tangentOS.w * GetOddNegativeScale());
    uv = texcoord0.xy;
    fogFactor = ComputeFogFactor(pos.positionCS.z);
}
#endif

// 片元里重建正交的 T/B/N（插值后会失去正交，Gram-Schmidt 修一下）
void Ch12BuildFrame(out vec3 T, out vec3 B, out vec3 N)
{
    N = normalize(normalWS);
    T = normalize(tangentWS.xyz - N * dot(tangentWS.xyz, N));
    B = cross(N, T) * tangentWS.w;
}
//#endregion

#endif
