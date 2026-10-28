// 案例 6.9 ClassicLit 的前向 Pass：归一化 Blinn-Phong + 球谐环境光 + 主光阴影 + 附加光（Forward / Forward+）
// + 附加光阴影 + Light Layers + 光照 Cookie + SSAO + 雾
#ifndef COOKBOOK_CH06_CLASSIC_LIT_FORWARD_PASS_INCLUDED
#define COOKBOOK_CH06_CLASSIC_LIT_FORWARD_PASS_INCLUDED

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

struct Attributes
{
    float4 positionOS : POSITION;
    float3 normalOS   : NORMAL;
    float2 texcoord   : TEXCOORD0;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct Varyings
{
    float4 positionCS : SV_POSITION;
    float2 uv         : TEXCOORD0;
    float3 positionWS : TEXCOORD1;
    float3 normalWS   : TEXCOORD2;
    half4  fogFactorAndVertexLight : TEXCOORD3;   // x：雾；yzw：逐顶点附加光
#if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
    float4 shadowCoord : TEXCOORD4;               // 不分级联时，阴影坐标可在顶点里算好再插值
#endif
    UNITY_VERTEX_INPUT_INSTANCE_ID
    UNITY_VERTEX_OUTPUT_STEREO
};

//#region vert
Varyings ClassicLitVertex(Attributes input)
{
    Varyings output = (Varyings)0;
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_TRANSFER_INSTANCE_ID(input, output);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

    VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
    half3 normalWS = TransformObjectToWorldNormal(input.normalOS);

    output.positionCS = vertexInput.positionCS;
    output.positionWS = vertexInput.positionWS;
    output.normalWS = normalWS;
    output.uv = TRANSFORM_TEX(input.texcoord, _BaseMap);

    half fogFactor = ComputeFogFactor(vertexInput.positionCS.z);
    half3 vertexLight = VertexLighting(vertexInput.positionWS, normalWS);   // 只有 _ADDITIONAL_LIGHTS_VERTEX 时非零
    output.fogFactorAndVertexLight = half4(fogFactor, vertexLight);

#if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
    output.shadowCoord = GetShadowCoord(vertexInput);
#endif
    return output;
}
//#endregion

//#region inputdata
InputData BuildInputData(Varyings input, half3 normalWS)
{
    InputData inputData = (InputData)0;
    inputData.positionWS = input.positionWS;
    inputData.positionCS = input.positionCS;
    inputData.normalWS = normalWS;
    inputData.viewDirectionWS = GetWorldSpaceNormalizeViewDir(input.positionWS);
#if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
    inputData.shadowCoord = input.shadowCoord;
#elif defined(MAIN_LIGHT_CALCULATE_SHADOWS)
    inputData.shadowCoord = TransformWorldToShadowCoord(input.positionWS);   // 级联：逐像素选级联
#else
    inputData.shadowCoord = float4(0, 0, 0, 0);
#endif
    // URP 14 强制逐像素算雾（ShaderVariablesFunctions.hlsl 里 #define _FOG_FRAGMENT 1），顶点雾因子只作后备
    inputData.fogCoord = InitializeInputDataFog(float4(input.positionWS, 1.0), input.fogFactorAndVertexLight.x);
    inputData.vertexLighting = input.fogFactorAndVertexLight.yzw;
    inputData.bakedGI = SampleSH(normalWS);                     // 本章只用球谐环境光，光照贴图见第 8 章
    inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(input.positionCS);
    inputData.shadowMask = half4(1, 1, 1, 1);                   // 没有烘焙阴影时为 1
    return inputData;
}
//#endregion

//#region blinnphong
// 一盏灯的贡献：归一化 Blinn-Phong（URP 约定，漫反射不除 π，高光系数为 (n+8)/8）
half3 ClassicBlinnPhong(Light light, half3 normalWS, half3 viewDirWS, half3 albedo, half3 specColor, float shininess)
{
    half NdotL = saturate(dot(normalWS, light.direction));
    half3 radiance = light.color * (light.distanceAttenuation * light.shadowAttenuation * NdotL);

    float3 H = SafeNormalize(float3(light.direction) + float3(viewDirWS));
    float NdotH = saturate(dot(float3(normalWS), H));
    float spec = (shininess + 8.0) * 0.125 * pow(NdotH, shininess);

    return (albedo + specColor * spec) * radiance;
}
//#endregion

//#region frag
half4 ClassicLitFragment(Varyings input) : SV_Target
{
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

    half4 baseSample = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv) * _BaseColor;
#if defined(_ALPHATEST_ON)
    clip(baseSample.a - _Cutoff);
#endif
    half3 albedo = baseSample.rgb;
    half3 specColor = _SpecColor.rgb;
    float shininess = exp2(10.0 * _Smoothness + 1.0);        // 与 URP SimpleLit 相同的映射

    half3 normalWS = NormalizeNormalPerPixel(input.normalWS);
    InputData inputData = BuildInputData(input, normalWS);    // 名字必须叫 inputData，LIGHT_LOOP_BEGIN 会用到

    half4 shadowMask = CalculateShadowMask(inputData);
    AmbientOcclusionFactor aoFactor = CreateAmbientOcclusionFactor(inputData.normalizedScreenSpaceUV, 1.0);
    uint meshRenderingLayers = GetMeshRenderingLayer();

    // ---- 环境光（SSAO 只压暗间接光，直接光按 Direct Lighting Strength 衰减）----
    half3 color = inputData.bakedGI * albedo * aoFactor.indirectAmbientOcclusion;

    // ---- 主光源：带阴影、阴影淡出和 Cookie ----
    Light mainLight = GetMainLight(inputData, shadowMask, aoFactor);
#if defined(_LIGHT_LAYERS)
    if (IsMatchingLightLayer(mainLight.layerMask, meshRenderingLayers))
#endif
        color += ClassicBlinnPhong(mainLight, normalWS, inputData.viewDirectionWS, albedo, specColor, shininess);

    // ---- 附加光源 ----
#if defined(_ADDITIONAL_LIGHTS)
    uint pixelLightCount = GetAdditionalLightsCount();

    #if USE_FORWARD_PLUS
    for (uint lightIndex = 0; lightIndex < min(URP_FP_DIRECTIONAL_LIGHTS_COUNT, MAX_VISIBLE_LIGHTS); lightIndex++)
    {
        FORWARD_PLUS_SUBTRACTIVE_LIGHT_CHECK
        Light light = GetAdditionalLight(lightIndex, inputData, shadowMask, aoFactor);
        #if defined(_LIGHT_LAYERS)
        if (IsMatchingLightLayer(light.layerMask, meshRenderingLayers))
        #endif
            color += ClassicBlinnPhong(light, normalWS, inputData.viewDirectionWS, albedo, specColor, shininess);
    }
    #endif

    LIGHT_LOOP_BEGIN(pixelLightCount)
        // 这个重载会顺带算出附加光阴影（_ADDITIONAL_LIGHT_SHADOWS）与 Cookie
        Light light = GetAdditionalLight(lightIndex, inputData, shadowMask, aoFactor);
        #if defined(_LIGHT_LAYERS)
        if (IsMatchingLightLayer(light.layerMask, meshRenderingLayers))
        #endif
            color += ClassicBlinnPhong(light, normalWS, inputData.viewDirectionWS, albedo, specColor, shininess);
    LIGHT_LOOP_END
#endif

#if defined(_ADDITIONAL_LIGHTS_VERTEX)
    color += inputData.vertexLighting * albedo;               // 逐顶点附加光：只有漫反射
#endif

    color += _EmissionColor.rgb;
    color = MixFog(color, inputData.fogCoord);
    return half4(color, baseSample.a);
}
//#endregion

#endif
