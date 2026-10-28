// 第 12 章自用的 BRDF 工具函数。
// 全部自己实现，不依赖其它章节；函数名统一加 Adv 前缀，避免和 core 包 BSDF.hlsl 里的 D_GGX、F_Schlick 等重名。
// 约定：roughness 指 α（= 感知粗糙度²），所有角度余弦都已经 saturate 过。
#ifndef COOKBOOK_CH12_ADV_BRDF_INCLUDED
#define COOKBOOK_CH12_ADV_BRDF_INCLUDED

#define ADV_PI     3.14159265
#define ADV_INV_PI 0.31830989

float AdvPow5(float x) { float x2 = x * x; return x2 * x2 * x; }

//#region iso
// ---------- 各向同性 GGX ----------
// D：Trowbridge-Reitz / GGX 法线分布
float AdvD_GGX(float NoH, float a)
{
    float a2 = a * a;
    float d = NoH * NoH * (a2 - 1.0) + 1.0;
    return a2 / (ADV_PI * d * d + 1e-7);
}

// V：高度相关 Smith 可见性项，V = G / (4 NoL NoV)，分母已经约掉
float AdvV_SmithGGX(float NoV, float NoL, float a)
{
    float a2 = a * a;
    float lambdaV = NoL * sqrt(NoV * NoV * (1.0 - a2) + a2);
    float lambdaL = NoV * sqrt(NoL * NoL * (1.0 - a2) + a2);
    return 0.5 / (lambdaV + lambdaL + 1e-5);
}

// F：Schlick 近似
float3 AdvF_Schlick(float3 f0, float f90, float VoH)
{
    return f0 + (f90 - f0) * AdvPow5(1.0 - VoH);
}
float AdvF_Schlick(float f0, float f90, float VoH)
{
    return f0 + (f90 - f0) * AdvPow5(1.0 - VoH);
}

// 标准金属度工作流的镜面项：D·V·F（返回值还要乘 NoL 和光强）
float3 AdvSpecularGGX(float3 N, float3 V, float3 L, float a, float3 f0)
{
    float3 H = normalize(V + L);
    float NoV = max(dot(N, V), 1e-4);
    float NoL = saturate(dot(N, L));
    float NoH = saturate(dot(N, H));
    float VoH = saturate(dot(V, H));
    return AdvD_GGX(NoH, a) * AdvV_SmithGGX(NoV, NoL, a) * AdvF_Schlick(f0, 1.0, VoH);
}
//#endregion

//#region envbrdf
// 环境 BRDF 的解析近似（Karis 2014，移动端常用）：返回 F0*A + B 里的 (A, B)
// 用感知粗糙度做输入，拟合的是 split-sum 第二项的预积分 LUT
float2 AdvEnvBRDFApprox(float perceptualRoughness, float NoV)
{
    const float4 c0 = float4(-1.0, -0.0275, -0.572, 0.022);
    const float4 c1 = float4( 1.0,  0.0425,  1.040, -0.040);
    float4 r = perceptualRoughness * c0 + c1;
    float a004 = min(r.x * r.x, exp2(-9.28 * NoV)) * r.x + r.y;
    return float2(-1.04, 1.04) * a004 + r.zw;
}
//#endregion

//#region aniso
// ---------- 各向异性 GGX（Burley 2012 / Heitz 2014）----------
// at、ab 分别是沿切线 T、副切线 B 方向的粗糙度 α
float AdvD_GGXAniso(float ToH, float BoH, float NoH, float at, float ab)
{
    float3 v = float3(ab * ToH, at * BoH, at * ab * NoH);
    float v2 = dot(v, v);
    float w2 = at * ab / max(v2, 1e-7);
    return at * ab * w2 * w2 * ADV_INV_PI;
}

float AdvV_SmithGGXAniso(float ToV, float BoV, float NoV, float ToL, float BoL, float NoL, float at, float ab)
{
    float lambdaV = NoL * length(float3(at * ToV, ab * BoV, NoV));
    float lambdaL = NoV * length(float3(at * ToL, ab * BoL, NoL));
    return 0.5 / (lambdaV + lambdaL + 1e-5);
}

// 由一个各向异性参数 k ∈ (-1,1) 拆出两个方向的粗糙度
// 本书约定：k > 0 表示“沿 T 光滑、垂直 T 粗糙”，即 T 就是拉丝（划痕）方向
void AdvAnisoRoughness(float a, float k, out float at, out float ab)
{
    at = max(a * (1.0 - k), 0.002);
    ab = max(a * (1.0 + k), 0.002);
}
//#endregion

//#region cloth
// ---------- 布料：Charlie sheen（Estevez & Kulla 2017）----------
// 形状是 sin(θh) 的幂：法线越接近垂直于 H（掠射）越亮，正好对应绒毛侧面反光
float AdvD_Charlie(float NoH, float a)
{
    float invA = 1.0 / a;
    float sin2h = max(1.0 - NoH * NoH, 1e-4);
    return (2.0 + invA) * pow(sin2h, invA * 0.5) / (2.0 * ADV_PI);
}

// Neubelt & Pettineo 2013 的布料可见性项，比 Charlie 原文的 V 便宜很多
float AdvV_Neubelt(float NoV, float NoL)
{
    return 1.0 / (4.0 * (NoL + NoV - NoL * NoV) + 1e-5);
}
//#endregion

//#region kk
// ---------- 头发：Kajiya-Kay ----------
// 沿发丝方向 T 的“圆柱”高光：sin(T,H) 越接近 1 越亮
float3 AdvShiftTangent(float3 T, float3 N, float shift)
{
    return normalize(T + shift * N);
}

float AdvKajiyaKay(float3 T, float3 H, float exponent)
{
    float ToH = dot(T, H);
    float sinTH = sqrt(max(1.0 - ToH * ToH, 0.0));
    // 背面衰减：H 跑到发丝“后面”时淡出，避免高光穿透（Scheuermann 2004 的做法）
    float dirAtten = smoothstep(-1.0, 0.0, ToH);
    return dirAtten * pow(sinTH, exponent);
}
//#endregion

//#region wrap
// ---------- 包裹漫反射（Wrap Lighting），w ∈ [0,1] ----------
// 除以 (1+w)² 是为了让半球积分仍然 ≈ 能量守恒
float AdvWrapDiffuse(float NoL_unclamped, float w)
{
    return saturate((NoL_unclamped + w) / ((1.0 + w) * (1.0 + w)));
}
//#endregion

//#region thinfilm
// ---------- 薄膜干涉 ----------
// CIE 1931 配色函数的多瓣高斯拟合（Wyman, Sloan & Shirley 2013）
float AdvG(float x, float mu, float s1, float s2)
{
    float t = (x - mu) / (x < mu ? s1 : s2);
    return exp(-0.5 * t * t);
}
float3 AdvWavelengthToXYZ(float lambda)
{
    float x = 1.056 * AdvG(lambda, 599.8, 37.9, 31.0) + 0.362 * AdvG(lambda, 442.0, 16.0, 26.7)
            - 0.065 * AdvG(lambda, 501.1, 20.4, 26.2);
    float y = 0.821 * AdvG(lambda, 568.8, 46.9, 40.5) + 0.286 * AdvG(lambda, 530.9, 16.3, 31.1);
    float z = 1.217 * AdvG(lambda, 437.0, 11.8, 36.0) + 0.681 * AdvG(lambda, 459.0, 26.0, 13.8);
    return float3(x, y, z);
}
float3 AdvXYZToLinearSRGB(float3 c)
{
    return float3( 3.2406 * c.x - 1.5372 * c.y - 0.4986 * c.z,
                  -0.9689 * c.x + 1.8758 * c.y + 0.0415 * c.z,
                   0.0557 * c.x - 0.2040 * c.y + 1.0570 * c.z);
}

// 单个波长下“空气(1) / 薄膜(n2，厚 d 纳米) / 基底”三层结构的反射率（Airy 公式）
// r12、r23 是带符号的振幅反射系数，符号里已经包含了半波损失（π 相位）
float AdvAiryReflectance(float r12, float r23, float opd, float lambda)
{
    float delta = 2.0 * ADV_PI * opd / lambda;   // 两束光的相位差
    float c = cos(delta);
    float num = r12 * r12 + r23 * r23 + 2.0 * r12 * r23 * c;
    float den = 1.0 + r12 * r12 * r23 * r23 + 2.0 * r12 * r23 * c;
    return num / den;
}

// 返回线性 sRGB 下的反射率颜色。cosTheta1：入射角余弦；thickness：膜厚（nm）；
// filmIOR：膜折射率；baseF0：基底在空气中的 F0（金属取其颜色亮度即可）
float3 AdvThinFilm(float cosTheta1, float thickness, float filmIOR, float baseF0)
{
    // 斯涅尔定律求膜内折射角
    float sin2 = (1.0 - cosTheta1 * cosTheta1) / (filmIOR * filmIOR);
    float cosTheta2 = sqrt(saturate(1.0 - sin2));
    float opd = 2.0 * filmIOR * thickness * cosTheta2;  // 光程差

    // 法向入射时的振幅反射系数，再用 Schlick 的角度项放大到掠射角
    float r12n = (1.0 - filmIOR) / (1.0 + filmIOR);                 // 空气→膜：负号=半波损失
    float baseIOR = (1.0 + sqrt(baseF0)) / (1.0 - sqrt(min(baseF0, 0.99)));
    float r23n = (filmIOR - baseIOR) / (filmIOR + baseIOR);
    float r12 = -sqrt(AdvF_Schlick(r12n * r12n, 1.0, cosTheta1));
    float r23 = sign(r23n) * sqrt(AdvF_Schlick(r23n * r23n, 1.0, cosTheta2));

    float3 xyz = 0, xyzWhite = 0;
    const int N = 16;
    [unroll] for (int i = 0; i < N; i++)
    {
        float lambda = 400.0 + 300.0 * (i + 0.5) / N;   // 400~700nm 等间隔采样
        float3 cmf = AdvWavelengthToXYZ(lambda);
        xyz      += cmf * AdvAiryReflectance(r12, r23, opd, lambda);
        xyzWhite += cmf;
    }
    // 用“反射率处处为 1”的光谱做归一化：常数反射率 → 中性灰
    float3 rgb = AdvXYZToLinearSRGB(xyz) / AdvXYZToLinearSRGB(xyzWhite);
    return max(rgb, 0.0);
}
//#endregion

#endif
