// 第 10 章两个对照 Shader（SpecCompare、SpecFurnace）用到的 core 包 BSDF.hlsl 标准函数（GLSL 版）。
// HLSL 版 include Lighting.hlsl 时顺带就有这些函数；网页版的公共光照库里没有，这里按 core 包原样抄一份。
#ifndef COOKBOOK_CH10_CORE_BSDF_INCLUDED
#define COOKBOOK_CH10_CORE_BSDF_INCLUDED

// Common.hlsl：分子分母相等时返回 1（避免 0/0）
float SafeDiv(float numer, float denom) { return (numer != denom) ? numer / denom : 1.0; }

// GGX 法线分布：D = α² / (π ((n·h)²(α²-1) + 1)²)
float D_GGXNoPI(float NdotH, float roughness)
{
    float a2 = roughness * roughness;
    float s = (NdotH * a2 - NdotH) * NdotH + 1.0;
    return SafeDiv(a2, s * s);
}
float D_GGX(float NdotH, float roughness) { return INV_PI * D_GGXNoPI(NdotH, roughness); }

// 高度相关 Smith 的可见性项 V = G / (4 (n·l)(n·v))
float GetSmithJointGGXPartLambdaV(float NdotV, float roughness)
{
    float a2 = roughness * roughness;
    return sqrt((-NdotV * a2 + NdotV) * NdotV + a2);
}
float V_SmithJointGGX(float NdotL, float NdotV, float roughness, float partLambdaV)
{
    float a2 = roughness * roughness;
    float lambdaV = NdotL * partLambdaV;
    float lambdaL = NdotV * sqrt((-NdotL * a2 + NdotL) * NdotL + a2);
    return 0.5 / max(lambdaV + lambdaL, FLT_MIN);
}
float V_SmithJointGGX(float NdotL, float NdotV, float roughness)
{
    return V_SmithJointGGX(NdotL, NdotV, roughness, GetSmithJointGGXPartLambdaV(NdotV, roughness));
}

// Schlick 菲涅尔
float F_Schlick(float f0, float f90, float u)
{
    float x = 1.0 - u;
    float x2 = x * x;
    float x5 = x * x2 * x2;
    return (f90 - f0) * x5 + f0;
}
vec3 F_Schlick(vec3 f0, float f90, float u)
{
    float x = 1.0 - u;
    float x2 = x * x;
    float x5 = x * x2 * x2;
    return (f90 - f0) * x5 + f0;
}
vec3 F_Schlick(vec3 f0, float u) { return F_Schlick(f0, 1.0, u); }

#endif
