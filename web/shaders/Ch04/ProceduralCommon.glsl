// 第 4 章所有“图案 Shader”共用的顶点部分：只需要位置和 UV。（GLSL 版，对应 Ch04/ProceduralCommon.hlsl）
// 用法：在 Pass 的 GLSLPROGRAM 里 #include 本文件，它提供顶点着色器（ProceduralVert）和插值变量 uv；
// 片元着色器（#ifdef FRAGMENT 的 main）由各个 Shader 自己写。
#ifndef COOKBOOK_CH04_PROCEDURAL_COMMON_INCLUDED
#define COOKBOOK_CH04_PROCEDURAL_COMMON_INCLUDED

#include "Ch04/ProceduralLib.glsl"

// HLSL 版的 Varyings 结构体：WebGL 不允许结构体做 varying，拆成单独变量（positionCS 就是 gl_Position）
VARYING vec2 uv;

#ifdef VERTEX
// ProceduralVert
void main()
{
    gl_Position = TransformObjectToHClip(positionOS.xyz);
    uv = texcoord0.xy;
}
#endif

#endif
