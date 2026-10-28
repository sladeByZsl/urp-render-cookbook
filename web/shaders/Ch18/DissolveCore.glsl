// 溶解效果的核心：材质参数 + “溶解值”计算。Forward、ShadowCaster、DepthOnly 三个 Pass 共用，
// 保证屏幕上的镂空、阴影里的镂空、深度图里的镂空完全一致。（GLSL 版，对应 DissolveCore.hlsl）
#ifndef COOKBOOK_CH18_DISSOLVE_CORE_INCLUDED
#define COOKBOOK_CH18_DISSOLVE_CORE_INCLUDED

uniform sampler2D _BaseMap;
uniform sampler2D _NoiseMap;
uniform sampler2D _EdgeRamp;

// HLSL 版要求所有 Pass 的 UnityPerMaterial 一模一样（SRP Batcher）；GLSL 里就是普通 uniform
uniform vec4  _BaseMap_ST;
uniform vec4  _BaseColor;
uniform float _Smoothness;
uniform vec4  _NoiseMap_ST;
uniform float _Progress;
uniform float _AutoPlay;
uniform float _EdgeWidth;
uniform vec4  _EdgeColor;
uniform float _UseRamp;
uniform float _NoiseStrength;
uniform vec4  _DissolveDir;     // xyz：对象空间方向
uniform vec4  _DirRange;        // x/y：沿方向的最小/最大投影（对象空间）
uniform vec4  _SphereCenter;    // xyz：世界空间球心，w：最大半径

//#region progress
float GetProgress()
{
    // 运行时可以勾选 AutoPlay 让它自己循环；书中拍图时 _Time 不可控，用 _Progress 手动给进度
    return _AutoPlay > 0.5 ? fract(_Time.y * 0.25) : _Progress;
}
//#endregion

//#region dissolveValue
// 返回 0~1 的“溶解值”：值越小越早消失。进度 p 时，值 < p 的像素被裁掉。
float DissolveValue(vec2 uv, vec3 positionOS, vec3 positionWS)
{
    float noise = texture(_NoiseMap, uv * _NoiseMap_ST.xy + _NoiseMap_ST.zw).r;
#if defined(_MODE_DIRECTION)
    // 方向溶解：沿对象空间某方向的投影，归一化到 0~1，再掺一点噪声让边缘不规则
    float h = dot(positionOS, normalize(_DissolveDir.xyz));
    float t = saturate((h - _DirRange.x) / (_DirRange.y - _DirRange.x));
    return mix(t, noise, _NoiseStrength);
#elif defined(_MODE_SPHERE)
    // 球形溶解：离球心越近越早消失，像被一个不断变大的球“吞掉”
    float t = saturate(distance(positionWS, _SphereCenter.xyz) / _SphereCenter.w);
    return mix(t, noise, _NoiseStrength);
#else
    return noise;
#endif
}
//#endregion

//#region clip
#ifdef FRAGMENT   // discard 只能出现在片元着色器里（HLSL 的 clip 也是）
// 把进度从 [0,1] 稍微外扩，保证 0 时完全可见、1 时完全消失（噪声图很少真正到 0 或 1）
float DissolveClip(float value, out float edge)
{
    float p = GetProgress() * (1.0 + _EdgeWidth + 0.02) - _EdgeWidth - 0.01;
    float d = value - p;          // d < 0：已经溶掉
    if (d < 0.0) discard;         // HLSL 的 clip(d)
    // 刚好在消失前沿附近的一条带子：d 从 0 到 EdgeWidth，edge 从 1 降到 0
    edge = 1.0 - saturate(d / max(_EdgeWidth, 1e-4));
    return d;
}
#endif
//#endregion

#endif
