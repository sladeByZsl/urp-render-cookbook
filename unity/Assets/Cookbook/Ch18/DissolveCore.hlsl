// 溶解效果的核心：材质参数 + “溶解值”计算。Forward、ShadowCaster、DepthOnly 三个 Pass 共用，
// 保证屏幕上的镂空、阴影里的镂空、深度图里的镂空完全一致。
#ifndef COOKBOOK_CH18_DISSOLVE_CORE_INCLUDED
#define COOKBOOK_CH18_DISSOLVE_CORE_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

TEXTURE2D(_BaseMap);  SAMPLER(sampler_BaseMap);
TEXTURE2D(_NoiseMap); SAMPLER(sampler_NoiseMap);
TEXTURE2D(_EdgeRamp); SAMPLER(sampler_EdgeRamp);

// 所有 Pass 的 UnityPerMaterial 必须一模一样，SRP Batcher 才认
CBUFFER_START(UnityPerMaterial)
    float4 _BaseMap_ST;
    half4  _BaseColor;
    half   _Smoothness;
    float4 _NoiseMap_ST;
    half   _Progress;
    half   _AutoPlay;
    half   _EdgeWidth;
    half4  _EdgeColor;
    half   _UseRamp;
    half   _NoiseStrength;
    float4 _DissolveDir;     // xyz：对象空间方向
    float4 _DirRange;        // x/y：沿方向的最小/最大投影（对象空间）
    float4 _SphereCenter;    // xyz：世界空间球心，w：最大半径
CBUFFER_END

//#region progress
half GetProgress()
{
    // 运行时可以勾选 AutoPlay 让它自己循环；书中拍图时 _Time 不可控，用 _Progress 手动给进度
    return _AutoPlay > 0.5 ? frac(_Time.y * 0.25) : _Progress;
}
//#endregion

//#region dissolveValue
// 返回 0~1 的“溶解值”：值越小越早消失。进度 p 时，值 < p 的像素被裁掉。
half DissolveValue(float2 uv, float3 positionOS, float3 positionWS)
{
    half noise = SAMPLE_TEXTURE2D(_NoiseMap, sampler_NoiseMap, uv * _NoiseMap_ST.xy + _NoiseMap_ST.zw).r;
#if defined(_MODE_DIRECTION)
    // 方向溶解：沿对象空间某方向的投影，归一化到 0~1，再掺一点噪声让边缘不规则
    float h = dot(positionOS, normalize(_DissolveDir.xyz));
    half t = saturate((h - _DirRange.x) / (_DirRange.y - _DirRange.x));
    return lerp(t, noise, _NoiseStrength);
#elif defined(_MODE_SPHERE)
    // 球形溶解：离球心越近越早消失，像被一个不断变大的球“吞掉”
    half t = saturate(distance(positionWS, _SphereCenter.xyz) / _SphereCenter.w);
    return lerp(t, noise, _NoiseStrength);
#else
    return noise;
#endif
}
//#endregion

//#region clip
// 把进度从 [0,1] 稍微外扩，保证 0 时完全可见、1 时完全消失（噪声图很少真正到 0 或 1）
half DissolveClip(half value, out half edge)
{
    half p = GetProgress() * (1.0h + _EdgeWidth + 0.02h) - _EdgeWidth - 0.01h;
    half d = value - p;          // d < 0：已经溶掉
    clip(d);
    // 刚好在消失前沿附近的一条带子：d 从 0 到 EdgeWidth，edge 从 1 降到 0
    edge = 1.0h - saturate(d / max(_EdgeWidth, 1e-4h));
    return d;
}
//#endregion

#endif
