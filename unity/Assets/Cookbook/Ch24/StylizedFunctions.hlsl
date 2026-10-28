// 第 24 章：卡通与溶解用到的 Custom Function。全部是纯数学，不依赖 URP 光照库，预览里也能正常工作。
#ifndef COOKBOOK_CH24_STYLIZED_INCLUDED
#define COOKBOOK_CH24_STYLIZED_INCLUDED

//#region toon
// 把 N·L 与阴影合成的“受光量”量化成 Steps 级色阶。
// Smooth 控制每一级台阶边缘的过渡宽度（0 = 硬边）。
void ToonRamp_float(float NdotL, float Shadow, float Steps, float Smooth, out float Ramp)
{
    // 先把 [-1,1] 的 N·L 半兰伯特化到 [0,1]。
    // 阴影不直接乘上去，而是把受光量“压”到明暗交界线（0.5）以下：背光面本来就暗，
    // 阴影贴图在交界线附近的锯齿就不会被色阶量化放大成一圈难看的齿边
    float lit = min(saturate(NdotL * 0.5 + 0.5), lerp(0.45, 1.0, Shadow));
    float x = lit * Steps;
    float level = floor(x);
    // 每一级台阶的上沿用 smoothstep 过渡到下一级；Smooth 取个下限，避免 smoothstep 两端相等时除零
    float blend = smoothstep(1.0 - max(Smooth, 1e-3), 1.0, frac(x));
    // 除以 (Steps-1)：Steps = 3 时输出 0 / 0.5 / 1 三个色阶
    Ramp = saturate((level + blend) / max(Steps - 1.0, 1.0));
}

void ToonRamp_half(half NdotL, half Shadow, half Steps, half Smooth, out half Ramp)
{
    float r;
    ToonRamp_float(NdotL, Shadow, Steps, Smooth, r);
    Ramp = r;
}
//#endregion

//#region rim
// 边缘光：视线与法线越垂直越亮；只在受光一侧出现时更像“轮廓被照亮”
void RimLight_float(float3 Normal, float3 ViewDir, float3 LightDir, float Power, float LightSideOnly, out float Rim)
{
    float fresnel = pow(1.0 - saturate(dot(normalize(Normal), normalize(ViewDir))), Power);
    float side = lerp(1.0, saturate(dot(Normal, LightDir) * 2.0 + 0.5), LightSideOnly);
    Rim = fresnel * side;
}

void RimLight_half(half3 Normal, half3 ViewDir, half3 LightDir, half Power, half LightSideOnly, out half Rim)
{
    float r;
    RimLight_float(Normal, ViewDir, LightDir, Power, LightSideOnly, r);
    Rim = r;
}
//#endregion

//#region dissolve
// 溶解：Noise 小于 Progress 的部分被裁掉；在裁剪边界外侧 EdgeWidth 范围内输出发光遮罩。
// AlphaOut 直接接 Master Stack 的 Alpha，Alpha Clip Threshold 填 0.5。
void Dissolve_float(float Noise, float Progress, float EdgeWidth, out float AlphaOut, out float Edge)
{
    // 让 Progress = 0 时完全不溶解、= 1 时完全消失：把阈值区间扩展到 [-EdgeWidth, 1]
    float threshold = Progress * (1.0 + EdgeWidth) - EdgeWidth;
    float d = Noise - threshold;           // > 0 保留，< 0 裁掉
    AlphaOut = step(0.0, d);
    Edge = 1.0 - smoothstep(0.0, EdgeWidth, d);   // 越靠近裁剪边界越接近 1
    Edge *= AlphaOut;
}

void Dissolve_half(half Noise, half Progress, half EdgeWidth, out half AlphaOut, out half Edge)
{
    float a, e;
    Dissolve_float(Noise, Progress, EdgeWidth, a, e);
    AlphaOut = a; Edge = e;
}
//#endregion

#endif
