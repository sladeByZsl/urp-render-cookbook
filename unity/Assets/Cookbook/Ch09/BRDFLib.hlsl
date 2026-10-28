#ifndef COOKBOOK_CH09_BRDFLIB_INCLUDED
#define COOKBOOK_CH09_BRDFLIB_INCLUDED

// 第 9 章用到的 BRDF 各项。
// 全部按“教科书形式”书写：保留 π、不合并常数、不做移动端近似，方便和正文公式逐项对照。
// 所有函数加 C9_ 前缀，避免与 core 包 BSDF.hlsl 里的 D_GGX / F_Schlick 等同名函数冲突。
// 约定：参数 a 一律是 α = perceptualRoughness²（见 9.11 节），不是材质面板上的 Smoothness。

//#region ndf
// ---------- 法线分布函数 D(h) ----------
// GGX / Trowbridge-Reitz：D = α² / (π · ((n·h)²(α²-1) + 1)²)
float C9_D_GGX(float NoH, float a)
{
    float a2 = a * a;
    float d = NoH * NoH * (a2 - 1.0) + 1.0;
    return a2 / (PI * d * d);
}

// Beckmann：D = exp(-tan²θh / α²) / (π α² cos⁴θh)
float C9_D_Beckmann(float NoH, float a)
{
    float a2 = a * a;
    float c2 = max(NoH * NoH, 1e-6);
    float t2 = (1.0 - c2) / c2;                 // tan²θh
    return exp(-t2 / a2) / (PI * a2 * c2 * c2);
}

// 归一化的 Blinn-Phong NDF：D = (n+2)/(2π) · cosⁿθh，指数 n 由 α 换算：n = 2/α² - 2
float C9_D_BlinnPhong(float NoH, float a)
{
    float n = 2.0 / max(a * a, 1e-4) - 2.0;
    return (n + 2.0) / (2.0 * PI) * pow(max(NoH, 0.0), n);
}
//#endregion

//#region geometry
// ---------- 几何遮蔽 G ----------
// GGX 的 Smith Λ 函数：Λ(θ) = (-1 + sqrt(1 + α² tan²θ)) / 2
float C9_Lambda_GGX(float NoX, float a)
{
    float c2 = max(NoX * NoX, 1e-6);
    float t2 = (1.0 - c2) / c2;
    return 0.5 * (-1.0 + sqrt(1.0 + a * a * t2));
}

// 单方向遮蔽 G1 = 1 / (1 + Λ)
float C9_G1_GGX(float NoX, float a) { return 1.0 / (1.0 + C9_Lambda_GGX(NoX, a)); }

// Smith 分离形式：G = G1(l) · G1(v)，假设“遮光”和“遮挡视线”互不相关
float C9_G_SmithSeparable(float NoL, float NoV, float a)
{
    return C9_G1_GGX(NoL, a) * C9_G1_GGX(NoV, a);
}

// Smith 高度相关形式（Height-Correlated）：G = 1 / (1 + Λ(l) + Λ(v))
float C9_G_SmithHeightCorrelated(float NoL, float NoV, float a)
{
    return 1.0 / (1.0 + C9_Lambda_GGX(NoL, a) + C9_Lambda_GGX(NoV, a));
}

// Schlick-GGX 近似：G1 ≈ n·x / (n·x (1-k) + k)，k = α/2
float C9_G_SchlickGGX(float NoL, float NoV, float a)
{
    float k = a * 0.5;
    float gl = NoL / (NoL * (1.0 - k) + k);
    float gv = NoV / (NoV * (1.0 - k) + k);
    return gl * gv;
}

// 可见性项 V = G / (4 (n·l)(n·v))，用高度相关 Smith 化简后的形式（Heitz 2014）
// V = 0.5 / ( n·l · sqrt((n·v)²(1-α²) + α²) + n·v · sqrt((n·l)²(1-α²) + α²) )
float C9_V_SmithHeightCorrelated(float NoL, float NoV, float a)
{
    float a2 = a * a;
    float lv = NoL * sqrt(NoV * NoV * (1.0 - a2) + a2);
    float ll = NoV * sqrt(NoL * NoL * (1.0 - a2) + a2);
    return 0.5 / max(lv + ll, 1e-5);
}
//#endregion

//#region fresnel
// ---------- 菲涅尔 F ----------
// Schlick 近似：F = F0 + (1 - F0)(1 - cosθ)⁵
float3 C9_F_Schlick(float3 F0, float cosTheta)
{
    float x = 1.0 - saturate(cosTheta);
    float x2 = x * x;
    return F0 + (1.0 - F0) * (x2 * x2 * x);
}
//#endregion

//#region diffuse
// ---------- 漫反射 ----------
// Lambert：f = ρ / π
float3 C9_Lambert(float3 albedo) { return albedo * INV_PI; }

// Disney（Burley 2012）漫反射：在 Lambert 基础上按粗糙度调整掠射角的明暗
// fd90 = 0.5 + 2 · (l·h)² · perceptualRoughness
float3 C9_DisneyDiffuse(float3 albedo, float NoL, float NoV, float LoH, float perceptualRoughness)
{
    float fd90 = 0.5 + 2.0 * LoH * LoH * perceptualRoughness;
    float lightScatter = 1.0 + (fd90 - 1.0) * pow(1.0 - NoL, 5.0);
    float viewScatter  = 1.0 + (fd90 - 1.0) * pow(1.0 - NoV, 5.0);
    return albedo * INV_PI * lightScatter * viewScatter;
}
//#endregion

#endif
