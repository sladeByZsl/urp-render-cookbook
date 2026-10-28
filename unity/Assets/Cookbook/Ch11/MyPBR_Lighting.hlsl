// MyPBR 的光照组装：直接光（主光 + 附加光，Forward / Forward+）+ 间接光（SH 漫反射 + IBL 镜面）。
// 从 URP 只拿“数据”：Light 结构体、阴影衰减、SH 系数、反射探针取样、SSAO；BRDF 全部来自 MyPBR_BRDF.hlsl。
#ifndef COOKBOOK_MYPBR_LIGHTING_INCLUDED
#define COOKBOOK_MYPBR_LIGHTING_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "Assets/Cookbook/Ch11/MyPBR_BRDF.hlsl"

// 分项结果：调试视图会单独显示每一项
struct MyLightingTerms
{
    float3 directDiffuse;
    float3 directSpecular;
    float3 indirectDiffuse;
    float3 indirectSpecular;
    float3 emission;
};

//#region evaluate_light
// 一盏灯对出射辐射率的贡献：Lo = f(l,v) * E⊥ * NoL
// Unity 的光源约定：light.color 是“白色 Lambert 表面正对灯时看到的亮度”，
// 即 Lo = albedo/π * E⊥  =>  E⊥ = π * light.color。所以这里乘 π，与 BRDF 里的 1/π 互相抵消。
void MyAccumulateLight(MyMaterial m, float3 N, float3 V, Light light, inout MyLightingTerms t)
{
    float3 fd, fs; float NoL;
    MyDirectBRDF(m, N, V, light.direction, fd, fs, NoL);
    float3 E = PI * light.color * (light.distanceAttenuation * light.shadowAttenuation) * NoL;
    t.directDiffuse  += fd * E;
    t.directSpecular += fs * E;
}
//#endregion

//#region env_sample
// 取预滤波环境图（split-sum 的第一项）
float3 MySamplePrefilteredEnv(float3 R, float perceptualRoughness, float3 positionWS, float2 screenUV)
{
#if USE_FORWARD_PLUS || defined(_REFLECTION_PROBE_BLENDING)
    // Forward+ 把所有反射探针打包进一张八面体图集，天空反射走 _GlossyEnvironmentCubeMap；
    // 探针混合也有一套权重逻辑。这些都是“取样”，与 BRDF 无关，直接复用 URP 的取样函数
    // （它内部同样用感知粗糙度选 mip，映射公式与 MyRoughnessToMip 相同）。
    return GlossyEnvironmentReflection(R, positionWS, perceptualRoughness, 1.0h, screenUV);
#else
    #if defined(_REFLECTION_PROBE_BOX_PROJECTION)
    R = BoxProjectedCubemapDirection(R, positionWS, unity_SpecCube0_ProbePosition,
                                     unity_SpecCube0_BoxMin, unity_SpecCube0_BoxMax);
    #endif
    float mip = MyRoughnessToMip(perceptualRoughness);
    half4 encoded = SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, R, mip);
    return DecodeHDREnvironment(encoded, unity_SpecCube0_HDR);   // 解 RGBM / HDR 编码
#endif
}
//#endregion

//#region compute_lighting
MyLightingTerms MyComputeLighting(MySurface s, inout MyMaterial m, InputData inputData)
{
    MyLightingTerms t = (MyLightingTerms)0;
    float3 N = inputData.normalWS;
    float3 V = inputData.viewDirectionWS;
    float NoV = saturate(dot(N, V)) + 1e-5;

    // ---- 环境 BRDF 与能量补偿：只和 NoV、粗糙度有关，先算好给直接光也用 ----
    float2 dfg = MyEnvDFG(NoV, m.perceptualRoughness);
    m.energyCompensation = lerp(1.0, MyEnergyCompensation(dfg, m.f0), _EnergyCompensation);

    // ---- 遮蔽：材质 AO 与 SSAO 取最小值（URP 的约定）----
    AmbientOcclusionFactor ao = CreateAmbientOcclusionFactor(inputData.normalizedScreenSpaceUV, s.occlusion);
    half4 shadowMask = CalculateShadowMask(inputData);
    uint meshLayers = GetMeshRenderingLayer();

    // ---- 主光 ----
    Light mainLight = GetMainLight(inputData, shadowMask, ao);   // 已含阴影、Light Cookie、SSAO 直接光部分
    MixRealtimeAndBakedGI(mainLight, N, inputData.bakedGI);      // Subtractive 光照贴图模式下扣掉主光
#if defined(_LIGHT_LAYERS)
    if (IsMatchingLightLayer(mainLight.layerMask, meshLayers))
#endif
        MyAccumulateLight(m, N, V, mainLight, t);

    // ---- 附加光：Forward 逐物体列表 / Forward+ 分簇列表 ----
#if defined(_ADDITIONAL_LIGHTS)
    uint lightCount = GetAdditionalLightsCount();

    #if USE_FORWARD_PLUS
    // Forward+ 下，除主光外的方向光不进分簇，排在附加光数组最前面，要单独循环
    for (uint lightIndex = 0; lightIndex < min(URP_FP_DIRECTIONAL_LIGHTS_COUNT, MAX_VISIBLE_LIGHTS); lightIndex++)
    {
        FORWARD_PLUS_SUBTRACTIVE_LIGHT_CHECK
        Light light = GetAdditionalLight(lightIndex, inputData, shadowMask, ao);
        #if defined(_LIGHT_LAYERS)
        if (IsMatchingLightLayer(light.layerMask, meshLayers))
        #endif
            MyAccumulateLight(m, N, V, light, t);
    }
    #endif

    // LIGHT_LOOP_BEGIN 在 Forward 下展开成 for 循环，在 Forward+ 下展开成分簇迭代器，
    // 宏内部会用到名为 inputData 的变量（normalizedScreenSpaceUV、positionWS）
    LIGHT_LOOP_BEGIN(lightCount)
        Light light = GetAdditionalLight(lightIndex, inputData, shadowMask, ao);
        #if defined(_LIGHT_LAYERS)
        if (IsMatchingLightLayer(light.layerMask, meshLayers))
        #endif
            MyAccumulateLight(m, N, V, light, t);
    LIGHT_LOOP_END
#endif

#if defined(_ADDITIONAL_LIGHTS_VERTEX)
    // 逐顶点附加光只有漫反射：顶点里累加的是 color * atten * NoL，等价于 E/π
    t.directDiffuse += inputData.vertexLighting * m.diffuseColor;
#endif

    // ---- 间接漫反射：SH（或光照贴图）----
    // Unity 的 SH / 光照贴图里存的是 E/π（“已经除过 π 的辐照度”），直接乘漫反射色即可
    t.indirectDiffuse = inputData.bakedGI * m.diffuseColor * ao.indirectAmbientOcclusion;

    // ---- 间接镜面：split-sum = 预滤波环境 × 环境 BRDF ----
    float3 R = reflect(-V, N);
    float3 prefiltered = MySamplePrefilteredEnv(R, m.perceptualRoughness, inputData.positionWS, inputData.normalizedScreenSpaceUV);
    float3 envBRDF = m.f0 * dfg.x + dfg.y;     // F90 = 1
    float specOcc = lerp(ao.indirectAmbientOcclusion,
                         MySpecularOcclusion(NoV, ao.indirectAmbientOcclusion, m.perceptualRoughness),
                         _SpecularOcclusion);
    t.indirectSpecular = prefiltered * envBRDF * m.energyCompensation * specOcc;

    t.emission = s.emission;
    return t;
}
//#endregion

#endif
