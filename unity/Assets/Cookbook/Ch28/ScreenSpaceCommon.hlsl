// 第 28 章屏幕空间效果的公共函数：读深度、重建世界坐标、视锥射线。
#ifndef COOKBOOK_CH28_SCREENSPACE_COMMON
#define COOKBOOK_CH28_SCREENSPACE_COMMON

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
// Blit.hlsl 提供全屏三角形顶点函数 Vert、Varyings（含 texcoord）和源纹理 _BlitTexture
#include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

//#region rawdepth
// 读“设备深度”，并统一成 ComputeWorldSpacePosition 需要的 NDC z
float SampleDeviceDepth(float2 uv)
{
    float d = SampleSceneDepth(uv);
#if !UNITY_REVERSED_Z
    // OpenGL 系：深度纹理是 [0,1]，而它的裁剪空间 z 是 [-1,1]
    d = lerp(UNITY_NEAR_CLIP_VALUE, 1, d);
#endif
    return d;
}

// 循环里采样深度要用显式 LOD 版本：带隐式导数的 SAMPLE_TEXTURE2D 在动态循环里
// 会逼编译器展开整个循环（Metal/D3D 都会报 unable to unroll loop）
float SampleSceneDepthLod(float2 uv)
{
    return SAMPLE_TEXTURE2D_X_LOD(_CameraDepthTexture, sampler_CameraDepthTexture, UnityStereoTransformScreenSpaceTex(uv), 0).r;
}

// 天空（没有写深度的像素）：Reversed-Z 下是 0，否则是 1
bool IsSkyDepth(float deviceDepth)
{
#if UNITY_REVERSED_Z
    return deviceDepth < 1e-6;
#else
    return deviceDepth > 1 - 1e-6;
#endif
}
//#endregion

//#region invvp
// 方法一：逆 VP 矩阵。uv + 深度 → NDC → 乘逆矩阵 → 齐次除法
float3 ReconstructPositionWS(float2 uv, float deviceDepth)
{
    return ComputeWorldSpacePosition(uv, deviceDepth, UNITY_MATRIX_I_VP);
}
//#endregion

//#region viewray
// 方法二：视锥射线。顶点着色器里算“相机 → 远裁剪面”的向量，光栅化线性插值后，
// 片元里乘上 0~1 的线性深度即可，每像素省掉一次 4x4 矩阵乘法和除法。
struct VaryingsRay
{
    float4 positionCS : SV_POSITION;
    float2 texcoord   : TEXCOORD0;
    float3 farRayWS   : TEXCOORD1;   // 相机位置 → 该像素对应的远裁剪面上的点
    UNITY_VERTEX_OUTPUT_STEREO
};

VaryingsRay VertRay(Attributes input)
{
    VaryingsRay output;
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);
#if SHADER_API_GLES
    float4 pos = input.positionOS;
    float2 uv  = input.uv;
#else
    float4 pos = GetFullScreenTriangleVertexPosition(input.vertexID);
    float2 uv  = GetFullScreenTriangleTexCoord(input.vertexID);
#endif
    output.positionCS = pos;
    output.texcoord   = uv * _BlitScaleBias.xy + _BlitScaleBias.zw;
    // 远平面上的点关于屏幕坐标是仿射（线性）的，所以只在 3 个顶点算、再插值，结果是精确的
    float3 farWS = ComputeWorldSpacePosition(output.texcoord, UNITY_RAW_FAR_CLIP_VALUE, UNITY_MATRIX_I_VP);
    output.farRayWS = farWS - _WorldSpaceCameraPos;
    return output;
}

float3 ReconstructPositionWSFromRay(float3 farRayWS, float rawDepth)
{
    // Linear01Depth = 观察空间深度 / 远裁剪面距离，正好是射线的缩放系数
    return _WorldSpaceCameraPos + farRayWS * Linear01Depth(rawDepth, _ZBufferParams);
}
//#endregion

#endif
