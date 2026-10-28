// 第 12 章的通用光源循环：主光（含阴影）+ 附加光（GLSL 版，对应 LightLoop.hlsl）。
// 用法（“模板式 include”）：在 include 本文件之前，先定义
//     struct MaterialCtx { ... };                         // 片元的材质与几何信息
//     vec3 ShadeOneLight(MaterialCtx m, Light light);     // 单个光源的出射辐射率（含 NoL、衰减、阴影）
// 然后调用 AccumulateDirectLighting(m, positionWS, screenUV)。
// GLSL 版说明：网页版只有 Forward 路径，没有 Forward+ 的分簇宏（LIGHT_LOOP_BEGIN），附加光就是普通 for 循环。
#ifndef COOKBOOK_CH12_LIGHTLOOP_INCLUDED
#define COOKBOOK_CH12_LIGHTLOOP_INCLUDED

//#region loop
vec3 AccumulateDirectLighting(MaterialCtx m, vec3 positionWS, vec2 screenUV)
{
    vec4 shadowMask = vec4(1.0);   // 本章不涉及 Shadowmask 烘焙，全 1 即可
    vec4 shadowCoord = TransformWorldToShadowCoord(positionWS);
    Light mainLight = GetMainLight(shadowCoord, positionWS, shadowMask);
    vec3 color = ShadeOneLight(m, mainLight);

#if defined(_ADDITIONAL_LIGHTS)
    int pixelLightCount = GetAdditionalLightsCount();
    for (int lightIndex = 0; lightIndex < pixelLightCount; lightIndex++)
    {
        color += ShadeOneLight(m, GetAdditionalLight(lightIndex, positionWS, shadowMask));
    }
#endif
    return color;
}
//#endregion

#endif
