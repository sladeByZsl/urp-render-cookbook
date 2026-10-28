// 第 12 章的通用光源循环：主光（含阴影）+ 附加光（Forward 与 Forward+ 两种写法）。
// 用法（“模板式 include”）：在 include 本文件之前，先定义
//     struct MaterialCtx { ... };                         // 片元的材质与几何信息
//     half3 ShadeOneLight(MaterialCtx m, Light light);    // 单个光源的出射辐射率（含 NoL、衰减、阴影）
// 然后调用 AccumulateDirectLighting(m, positionWS, screenUV)。
#ifndef COOKBOOK_CH12_LIGHTLOOP_INCLUDED
#define COOKBOOK_CH12_LIGHTLOOP_INCLUDED

//#region loop
half3 AccumulateDirectLighting(MaterialCtx m, float3 positionWS, float2 screenUV)
{
    half4 shadowMask = half4(1, 1, 1, 1);   // 本章不涉及 Shadowmask 烘焙，全 1 即可
    float4 shadowCoord = TransformWorldToShadowCoord(positionWS);
    Light mainLight = GetMainLight(shadowCoord, positionWS, shadowMask);
    half3 color = ShadeOneLight(m, mainLight);

#if defined(_ADDITIONAL_LIGHTS)
    // Forward+ 的 LIGHT_LOOP_BEGIN 宏内部直接引用名为 inputData 的变量
    InputData inputData = (InputData)0;
    inputData.positionWS = positionWS;
    inputData.normalizedScreenSpaceUV = screenUV;

  #if USE_FORWARD_PLUS
    // Forward+ 把“额外的方向光”单独放在列表最前面，不参与分簇
    for (uint li = 0; li < min(URP_FP_DIRECTIONAL_LIGHTS_COUNT, MAX_VISIBLE_LIGHTS); li++)
    {
        color += ShadeOneLight(m, GetAdditionalLight(li, positionWS, shadowMask));
    }
  #endif

    uint pixelLightCount = GetAdditionalLightsCount();
    LIGHT_LOOP_BEGIN(pixelLightCount)
        color += ShadeOneLight(m, GetAdditionalLight(lightIndex, positionWS, shadowMask));
    LIGHT_LOOP_END
#endif
    return color;
}
//#endregion

#endif
