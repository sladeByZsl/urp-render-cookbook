// MyPBR 的光照组装：直接光（主光 + 附加光）+ 间接光（SH 漫反射 + IBL 镜面）。（GLSL 版，对应 Ch11/MyPBR_Lighting.hlsl）
// 从 URP 只拿“数据”：Light 结构体、阴影衰减、SH 系数、反射探针取样、SSAO；BRDF 全部来自 MyPBR_BRDF.glsl。
#ifndef COOKBOOK_MYPBR_LIGHTING_INCLUDED
#define COOKBOOK_MYPBR_LIGHTING_INCLUDED

#include "Ch11/MyPBR_BRDF.glsl"

// 分项结果：调试视图会单独显示每一项
struct MyLightingTerms
{
    vec3 directDiffuse;
    vec3 directSpecular;
    vec3 indirectDiffuse;
    vec3 indirectSpecular;
    vec3 emission;
};

// URP 的 GetMainLight(inputData, shadowMask, aoFactor) / GetAdditionalLight(i, inputData, shadowMask, aoFactor)：
// 取灯 + 阴影（含远处淡出）+ SSAO 的“直接光遮蔽”部分。网页版核心库没有这两个重载，在这里补上。
Light MyGetMainLight(InputData inputData, vec4 shadowMask, AmbientOcclusionFactor aoFactor)
{
    Light light = GetMainLight(inputData.shadowCoord, inputData.positionWS, shadowMask);
    light.color *= aoFactor.directAmbientOcclusion;
    return light;
}
Light MyGetAdditionalLight(int lightIndex, InputData inputData, vec4 shadowMask, AmbientOcclusionFactor aoFactor)
{
    Light light = GetAdditionalLight(lightIndex, inputData.positionWS, shadowMask);
    light.color *= aoFactor.directAmbientOcclusion;
    return light;
}

//#region evaluate_light
// 一盏灯对出射辐射率的贡献：Lo = f(l,v) * E⊥ * NoL
// Unity 的光源约定：light.color 是“白色 Lambert 表面正对灯时看到的亮度”，
// 即 Lo = albedo/π * E⊥  =>  E⊥ = π * light.color。所以这里乘 π，与 BRDF 里的 1/π 互相抵消。
void MyAccumulateLight(MyMaterial m, vec3 N, vec3 V, Light light, inout MyLightingTerms t)
{
    vec3 fd, fs; float NoL;
    MyDirectBRDF(m, N, V, light.direction, fd, fs, NoL);
    vec3 E = PI * light.color * (light.distanceAttenuation * light.shadowAttenuation) * NoL;
    t.directDiffuse  += fd * E;
    t.directSpecular += fs * E;
}
//#endregion

//#region env_sample
// 取预滤波环境图（split-sum 的第一项）
// HLSL 版在 Forward+ / 探针混合时改用 URP 的 GlossyEnvironmentReflection（反射探针图集）；
// 网页版只有一个反射立方体图 unity_SpecCube0，两条路径结果相同，这里只保留手写的那条。
vec3 MySamplePrefilteredEnv(vec3 R, float perceptualRoughness, vec3 positionWS, vec2 screenUV)
{
    float mip = MyRoughnessToMip(perceptualRoughness);
    vec4 encoded = textureLod(unity_SpecCube0, R, mip);
    return DecodeHDREnvironment(encoded, unity_SpecCube0_HDR);   // 解 RGBM / HDR 编码
}
//#endregion

//#region compute_lighting
MyLightingTerms MyComputeLighting(MySurface s, inout MyMaterial m, InputData inputData)
{
    MyLightingTerms t;
    t.directDiffuse = vec3(0.0); t.directSpecular = vec3(0.0);
    t.indirectDiffuse = vec3(0.0); t.indirectSpecular = vec3(0.0); t.emission = vec3(0.0);
    vec3 N = inputData.normalWS;
    vec3 V = inputData.viewDirectionWS;
    float NoV = saturate(dot(N, V)) + 1e-5;

    // ---- 环境 BRDF 与能量补偿：只和 NoV、粗糙度有关，先算好给直接光也用 ----
    vec2 dfg = MyEnvDFG(NoV, m.perceptualRoughness);
    m.energyCompensation = mix(vec3(1.0), MyEnergyCompensation(dfg, m.f0), _EnergyCompensation);

    // ---- 遮蔽：材质 AO 与 SSAO 取最小值（URP 的约定）----
    AmbientOcclusionFactor ao = GetScreenSpaceAmbientOcclusion(inputData.normalizedScreenSpaceUV);
    ao.indirectAmbientOcclusion = min(ao.indirectAmbientOcclusion, s.occlusion);
    vec4 shadowMask = inputData.shadowMask;

    // ---- 主光 ----
    Light mainLight = MyGetMainLight(inputData, shadowMask, ao);   // 已含阴影、SSAO 直接光部分
    // （HLSL 版这里还有 MixRealtimeAndBakedGI 与 Light Layers 判断；网页版没有光照贴图和灯光层）
    MyAccumulateLight(m, N, V, mainLight, t);

    // ---- 附加光：Forward 逐物体列表 / Forward+ 全部可见光 ----
#if defined(_ADDITIONAL_LIGHTS)
    // HLSL 版用 LIGHT_LOOP_BEGIN/END（Forward+ 下展开成分簇迭代器）；
    // 网页版的 GetAdditionalLightsCount() 已经按渲染路径返回本像素要算的灯数，普通 for 循环即可
    int lightCount = GetAdditionalLightsCount();
    for (int lightIndex = 0; lightIndex < lightCount; lightIndex++)
    {
        Light light = MyGetAdditionalLight(lightIndex, inputData, shadowMask, ao);
        MyAccumulateLight(m, N, V, light, t);
    }
#endif

#if defined(_ADDITIONAL_LIGHTS_VERTEX)
    // 逐顶点附加光只有漫反射：顶点里累加的是 color * atten * NoL，等价于 E/π
    t.directDiffuse += inputData.vertexLighting * m.diffuseColor;
#endif

    // ---- 间接漫反射：SH（或光照贴图）----
    // Unity 的 SH / 光照贴图里存的是 E/π（“已经除过 π 的辐照度”），直接乘漫反射色即可
    t.indirectDiffuse = inputData.bakedGI * m.diffuseColor * ao.indirectAmbientOcclusion;

    // ---- 间接镜面：split-sum = 预滤波环境 × 环境 BRDF ----
    vec3 R = reflect(-V, N);
    vec3 prefiltered = MySamplePrefilteredEnv(R, m.perceptualRoughness, inputData.positionWS, inputData.normalizedScreenSpaceUV);
    vec3 envBRDF = m.f0 * dfg.x + dfg.y;     // F90 = 1
    float specOcc = mix(ao.indirectAmbientOcclusion,
                        MySpecularOcclusion(NoV, ao.indirectAmbientOcclusion, m.perceptualRoughness),
                        _SpecularOcclusion);
    t.indirectSpecular = prefiltered * envBRDF * m.energyCompensation * specOcc;

    t.emission = s.emission;
    return t;
}
//#endregion

#endif
