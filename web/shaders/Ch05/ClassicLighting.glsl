// 案例 5.9 经典光照模型函数库（GLSL 版，对应 Ch05/ClassicLighting.hlsl）。
// 约定（与 URP 一致）：所有函数的返回值都已经乘过 N·L（或它的替代品），
// 而且没有除以 π——URP 的漫反射写作 albedo * lightColor * N·L，高光的归一化系数因此也整体乘了 π。
#ifndef COOKBOOK_CH05_CLASSIC_LIGHTING_INCLUDED
#define COOKBOOK_CH05_CLASSIC_LIGHTING_INCLUDED

//#region diffuse
float DiffuseLambert(vec3 N, vec3 L)
{
    return saturate(dot(N, L));
}

float DiffuseHalfLambert(vec3 N, vec3 L, float power)
{
    return pow(dot(N, L) * 0.5 + 0.5, power);
}

// 能量守恒的 Wrap：w = 0 时等于 Lambert
float DiffuseWrap(vec3 N, vec3 L, float w)
{
    return saturate((dot(N, L) + w) / ((1.0 + w) * (1.0 + w)));
}

// Oren-Nayar 定性模型（无三角函数版本），sigma 为微表面坡度的标准差（弧度）
float DiffuseOrenNayar(vec3 N, vec3 L, vec3 V, float sigma)
{
    float NdotL = saturate(dot(N, L));
    float NdotV = saturate(dot(N, V));
    float s2 = sigma * sigma;
    float A = 1.0 - 0.5 * s2 / (s2 + 0.33);
    float B = 0.45 * s2 / (s2 + 0.09);
    float s = dot(L, V) - NdotL * NdotV;
    return NdotL * (A + B * max(0.0, s) / max(max(NdotL, NdotV), 1e-4));
}
//#endregion

//#region specular
// 归一化 Phong：(n+2)/2 · (R·V)^n · N·L
float SpecularPhong(vec3 N, vec3 L, vec3 V, float n)
{
    float RdotV = saturate(dot(reflect(-L, N), V));
    return (n + 2.0) * 0.5 * pow(RdotV, n) * saturate(dot(N, L));
}

// 归一化 Blinn-Phong：(n+8)/8 · (N·H)^n · N·L
float SpecularBlinnPhong(vec3 N, vec3 L, vec3 V, float n)
{
    vec3 H = SafeNormalize(L + V);
    return (n + 8.0) * 0.125 * pow(saturate(dot(N, H)), n) * saturate(dot(N, L));
}

// 用 0~1 的“光滑度”驱动高光指数，映射与 URP SimpleLit 相同：smoothness=0 → 2，=1 → 2048
float ShininessFromSmoothness(float smoothness)
{
    return exp2(10.0 * smoothness + 1.0);
}
//#endregion

#endif
