// MyPBR 的 BRDF：全部自己写，不调用 URP 的 BRDF.hlsl / BSDF.hlsl 里的任何函数。
//   镜面：Cook-Torrance  f_s = D * V * F
//         D = GGX(Trowbridge-Reitz)      V = 高度相关 Smith 可见性项（已含 1/(4 NoL NoV)）
//         F = Schlick 近似
//   漫反射：Lambert  f_d = diffuseColor / π
//   环境：split-sum，环境 BRDF 用解析近似或程序生成的 DFG LUT
#ifndef COOKBOOK_MYPBR_BRDF_INCLUDED
#define COOKBOOK_MYPBR_BRDF_INCLUDED

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/GlobalSamplers.hlsl"   // sampler_LinearClamp

#define MY_DIELECTRIC_F0          0.04   // 常见电介质（折射率约 1.5）正入射反射率
#define MY_MIN_PERCEPTUAL_ROUGHNESS 0.045 // 防止点光源高光无限小、half 精度溢出
#ifndef UNITY_SPECCUBE_LOD_STEPS
#define UNITY_SPECCUBE_LOD_STEPS 6        // 反射探针最后一级 mip 的序号（与 core 的 ImageBasedLighting.hlsl 相同）
#endif

//#region brdf_terms
// 法线分布函数 D：GGX / Trowbridge-Reitz
//   D(h) = a² / ( π ( (n·h)² (a² - 1) + 1 )² )
float MyD_GGX(float NoH, float a2)
{
    float d = (NoH * a2 - NoH) * NoH + 1.0;   // = NoH²(a²-1)+1，写成两次 MAD
    return a2 / (PI * d * d);
}

// 可见性项 V = G2 / (4 NoL NoV)，G2 用高度相关（Height-Correlated）Smith-GGX
//   V = 0.5 / ( NoL * sqrt(NoV²(1-a²) + a²) + NoV * sqrt(NoL²(1-a²) + a²) )
float MyV_SmithGGXCorrelated(float NoV, float NoL, float a2)
{
    float lambdaV = NoL * sqrt((NoV - NoV * a2) * NoV + a2);
    float lambdaL = NoV * sqrt((NoL - NoL * a2) * NoL + a2);
    return 0.5 / max(lambdaV + lambdaL, 1e-5);
}

// 菲涅尔 F：Schlick 近似  F = F0 + (F90 - F0)(1 - cosθ)^5
float3 MyF_Schlick(float3 f0, float f90, float cosTheta)
{
    float x  = 1.0 - cosTheta;
    float x2 = x * x;
    float x5 = x2 * x2 * x;                    // 手写 pow5，比 pow() 便宜且没有 pow(0,5) 的边界问题
    return f0 + (f90 - f0) * x5;
}

// 漫反射：Lambert。能量守恒要求 ∫ f_d cosθ dω = albedo，所以要除以 π
float MyFd_Lambert()
{
    return INV_PI;
}
//#endregion

//#region material
// 由表面参数推出 BRDF 需要的量（与光源无关，每像素算一次）
struct MyMaterial
{
    float3 diffuseColor;        // 进入 Lambert 的颜色
    float3 f0;                  // 正入射镜面反射率
    float  perceptualRoughness;
    float  a2;                  // α² ，α = perceptualRoughness²
    float3 energyCompensation;  // 多次散射补偿系数，由 DFG 算出，默认 1
};

MyMaterial MyInitMaterial(half3 albedo, half metallic, half perceptualRoughness)
{
    MyMaterial m;
    // 金属度工作流：金属没有漫反射，基础色就是 F0；电介质 F0 固定 0.04，基础色进漫反射。
    // 电介质表面先被镜面反射走约 4%，剩下的才进入次表面形成漫反射，所以乘 (1 - 0.04)
    m.diffuseColor = albedo * (1.0 - metallic) * (1.0 - MY_DIELECTRIC_F0);
    m.f0 = lerp(MY_DIELECTRIC_F0.xxx, albedo, metallic);
    m.perceptualRoughness = max(perceptualRoughness, MY_MIN_PERCEPTUAL_ROUGHNESS);
    float a = m.perceptualRoughness * m.perceptualRoughness;   // 感知粗糙度平方 = GGX 的 α
    m.a2 = a * a;
    m.energyCompensation = 1.0;
    return m;
}
//#endregion

//#region direct_brdf
// 单个光源方向 L 上的 BRDF：分别返回漫反射项 fd 与镜面项 fs（单位 1/sr），
// 还没乘入射光和 NoL —— 那是“光照”的事，不是“材质”的事。
void MyDirectBRDF(MyMaterial m, float3 N, float3 V, float3 L,
                  out float3 fd, out float3 fs, out float NoL)
{
    float3 H = SafeNormalize(L + V);
    float NoV = abs(dot(N, V)) + 1e-5;         // 法线贴图会让 N 背向视线，取绝对值避免除 0
    NoL = saturate(dot(N, L));
    float NoH = saturate(dot(N, H));
    float LoH = saturate(dot(L, H));           // = VoH，半角向量两侧对称

    float  D   = MyD_GGX(NoH, m.a2);
    float  Vis = MyV_SmithGGXCorrelated(NoV, NoL, m.a2);
    float3 F   = MyF_Schlick(m.f0, 1.0, LoH);

    fs = (D * Vis) * F * m.energyCompensation;
    fd = m.diffuseColor * MyFd_Lambert();
}
//#endregion

//#region env_brdf
// 环境 BRDF（split-sum 的第二项）：∫ f_s cosθ dω = F0 * A + F90 * B
// 解析近似：Karis 2014《Physically Based Shading on Mobile》中的拟合，输入感知粗糙度
float2 MyEnvDFGApprox(float NoV, float perceptualRoughness)
{
    const float4 c0 = float4(-1.0, -0.0275, -0.572, 0.022);
    const float4 c1 = float4( 1.0,  0.0425,  1.040, -0.040);
    float4 r = perceptualRoughness * c0 + c1;
    float a004 = min(r.x * r.x, exp2(-9.28 * NoV)) * r.x + r.y;
    return float2(-1.04, 1.04) * a004 + r.zw;          // x = A（乘 F0），y = B（乘 F90）
}

// 程序生成的 LUT：u = NoV，v = 感知粗糙度；生成代码见 DFGLut.cs
float2 MyEnvDFG(float NoV, float perceptualRoughness)
{
#if defined(_DFG_LUT)
    return SAMPLE_TEXTURE2D_LOD(_DFGLut, sampler_LinearClamp, float2(NoV, perceptualRoughness), 0).rg;
#else
    return MyEnvDFGApprox(NoV, perceptualRoughness);
#endif
}

// 多次散射能量补偿（Kulla-Conty 思路的廉价版本，Fdez-Agüero 2019 / Filament 的做法）：
// 单次散射的方向反照率 Ess = A + B（取 F0 = 1），丢掉的能量是 1 - Ess。
// 把镜面整体放大 1 + F0 (1/Ess - 1)，粗糙金属不再“越粗越暗”。
float3 MyEnergyCompensation(float2 dfg, float3 f0)
{
    float Ess = max(dfg.x + dfg.y, 1e-4);
    return 1.0 + f0 * (1.0 / Ess - 1.0);
}

// 镜面遮蔽：由 AO 推一个对镜面也合理的遮蔽量（Lagarde & de Rousiers 2014 的经验公式）
float MySpecularOcclusion(float NoV, float ao, float perceptualRoughness)
{
    float a = perceptualRoughness * perceptualRoughness;
    return saturate(pow(abs(NoV + ao), exp2(-16.0 * a - 1.0)) - 1.0 + ao);
}

// 感知粗糙度 -> 预滤波 cubemap 的 mip 级。UNITY_SPECCUBE_LOD_STEPS = 6（最后一级的序号）。
// 非线性映射让低粗糙度区间分到更多 mip 级（与 URP 的取法一致，便于对照）。
float MyRoughnessToMip(float perceptualRoughness)
{
    return perceptualRoughness * (1.7 - 0.7 * perceptualRoughness) * UNITY_SPECCUBE_LOD_STEPS;
}
//#endregion

#endif
