// 第 28 章屏幕空间效果的公共函数：读深度、重建世界坐标、视锥射线。
// （Core.glsl 已经提供 SampleSceneDepth、ComputeWorldSpacePosition、Linear01Depth、_BlitTexture 等）
// 用法：Pass 里 #include "Ch28/ScreenSpaceCommon.glsl"；需要视锥射线的 Pass 先 #define USE_VIEW_RAY 再 include。

//#region rawdepth
// 读“设备深度”，并统一成 ComputeWorldSpacePosition 需要的格式。
// HLSL 版在 OpenGL 系平台要把 [0,1] 换成 NDC 的 [-1,1]；网页版的 ComputeWorldSpacePosition 自己做这一步，所以直接返回。
float SampleDeviceDepth(vec2 uv)
{
    return SampleSceneDepth(uv);
}

// 循环里采样深度用显式 LOD 版本（HLSL 里为了避免循环被强制展开）
float SampleSceneDepthLod(vec2 uv)
{
    return textureLod(_CameraDepthTexture, uv, 0.0).r;
}

// 天空（没有写深度的像素）：WebGL 深度不反转，天空是 1
bool IsSkyDepth(float deviceDepth)
{
#if UNITY_REVERSED_Z
    return deviceDepth < 1e-6;
#else
    return deviceDepth > 1.0 - 1e-6;
#endif
}
//#endregion

//#region invvp
// 方法一：逆 VP 矩阵。uv + 深度 → NDC → 乘逆矩阵 → 齐次除法
vec3 ReconstructPositionWS(vec2 uv, float deviceDepth)
{
    return ComputeWorldSpacePosition(uv, deviceDepth, UNITY_MATRIX_I_VP);
}
//#endregion

//#region viewray
// 方法二：视锥射线。顶点着色器里算“相机 → 远裁剪面”的向量，光栅化线性插值后，
// 片元里乘上 0~1 的线性深度即可，每像素省掉一次 4x4 矩阵乘法和除法。
// （HLSL 的 VaryingsRay 结构体在 GLSL 里拆成两个 varying：texcoord 和 farRayWS）
VARYING vec2 texcoord;
#ifdef USE_VIEW_RAY
VARYING vec3 farRayWS;   // 相机位置 → 该像素对应的远裁剪面上的点
#endif
#ifdef VERTEX
void main()
{
    vec2 p = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);
    gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
    texcoord = p * _BlitScaleBias.xy + _BlitScaleBias.zw;
#ifdef USE_VIEW_RAY
    // 远平面上的点关于屏幕坐标是仿射（线性）的，所以只在 3 个顶点算、再插值，结果是精确的
    vec3 farWS = ComputeWorldSpacePosition(texcoord, UNITY_RAW_FAR_CLIP_VALUE, UNITY_MATRIX_I_VP);
    farRayWS = farWS - _WorldSpaceCameraPos;
#endif
}
#endif

vec3 ReconstructPositionWSFromRay(vec3 farRay, float rawDepth)
{
    // Linear01Depth = 观察空间深度 / 远裁剪面距离，正好是射线的缩放系数
    return _WorldSpaceCameraPos + farRay * Linear01Depth(rawDepth, _ZBufferParams);
}
//#endregion

// 点采样（HLSL 的 sampler_PointClamp）
vec4 SamplePointClamp(sampler2D t, vec2 uv)
{
    ivec2 sz = textureSize(t, 0);
    return texelFetch(t, clamp(ivec2(uv * vec2(sz)), ivec2(0), sz - 1), 0);
}
