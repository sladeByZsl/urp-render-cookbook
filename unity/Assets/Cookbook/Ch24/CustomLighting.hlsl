// 第 24 章：给 Shader Graph 的 Custom Function 节点（Type = File）用的光照函数。
// 规则回顾：
//   1) 节点里填的 Name 是 "MainLight"，Shader Graph 会按节点精度调用 MainLight_float 或 MainLight_half，
//      所以两个后缀的版本最好都提供；
//   2) 所有输出都用 out 参数，函数返回 void；参数顺序 = 节点上 Inputs 在前、Outputs 在后，名字随意但顺序必须一致；
//   3) 节点预览（SHADERGRAPH_PREVIEW）由 Shader Graph 自己生成，不包含 URP 的 Lighting.hlsl，
//      GetMainLight 等函数在那里根本不存在，必须用 #if 给预览一个替身。
#ifndef COOKBOOK_CH24_CUSTOM_LIGHTING_INCLUDED
#define COOKBOOK_CH24_CUSTOM_LIGHTING_INCLUDED

//#region mainlight
void MainLight_float(float3 WorldPos, out float3 Direction, out float3 Color,
                     out float DistanceAtten, out float ShadowAtten)
{
#if defined(SHADERGRAPH_PREVIEW)
    // 预览球：给一个固定的斜上方光，不算阴影
    Direction = normalize(float3(0.5, 0.5, -0.3));
    Color = float3(1, 1, 1);
    DistanceAtten = 1;
    ShadowAtten = 1;
#else
    // 在片元阶段逐像素求阴影坐标：同时兼容无级联、级联和屏幕空间阴影三种关键字
    float4 shadowCoord = TransformWorldToShadowCoord(WorldPos);
    // 带 positionWS 的重载会顺带做“阴影距离淡出”，与 URP Lit 行为一致
    Light light = GetMainLight(shadowCoord, WorldPos, half4(1, 1, 1, 1));
    Direction = light.direction;
    Color = light.color;
    DistanceAtten = light.distanceAttenuation;
    ShadowAtten = light.shadowAttenuation;
#endif
}

void MainLight_half(half3 WorldPos, out half3 Direction, out half3 Color,
                    out half DistanceAtten, out half ShadowAtten)
{
    // half 版本直接转调 float 版本。注意：世界坐标一旦以 half 传进来就已经丢了精度（离原点远时阴影会抖），
    // 所以实际项目里建议把这个节点的 Precision 设成 Single，让 Shader Graph 调用 _float 版本
    float3 d, c; float da, sa;
    MainLight_float(WorldPos, d, c, da, sa);
    Direction = d; Color = c; DistanceAtten = da; ShadowAtten = sa;
}
//#endregion

//#region additional
// 所有附加光（点光、聚光）的 Lambert 漫反射之和。
// ScreenUV 接 Screen Position 节点（Default 模式），Forward+ 的分簇查询需要它。
void AdditionalLightsLambert_float(float3 WorldPos, float3 WorldNormal, float2 ScreenUV, out float3 Diffuse)
{
    Diffuse = 0;
#if !defined(SHADERGRAPH_PREVIEW)
    // LIGHT_LOOP_BEGIN 在 Forward+ 下会读取名为 inputData 的变量，所以这里按约定造一个
    InputData inputData = (InputData)0;
    inputData.positionWS = WorldPos;
    inputData.normalizedScreenSpaceUV = ScreenUV;

    uint lightCount = GetAdditionalLightsCount();
    #if USE_FORWARD_PLUS
    // Forward+ 把额外的方向光放在索引最前面，单独循环
    for (uint lightIndex = 0; lightIndex < min(URP_FP_DIRECTIONAL_LIGHTS_COUNT, MAX_VISIBLE_LIGHTS); lightIndex++)
    {
        Light light = GetAdditionalLight(lightIndex, WorldPos, half4(1, 1, 1, 1));
        Diffuse += light.color * light.distanceAttenuation * light.shadowAttenuation * saturate(dot(WorldNormal, light.direction));
    }
    #endif
    LIGHT_LOOP_BEGIN(lightCount)
        Light light = GetAdditionalLight(lightIndex, WorldPos, half4(1, 1, 1, 1));
        Diffuse += light.color * light.distanceAttenuation * light.shadowAttenuation * saturate(dot(WorldNormal, light.direction));
    LIGHT_LOOP_END
#endif
}

void AdditionalLightsLambert_half(half3 WorldPos, half3 WorldNormal, half2 ScreenUV, out half3 Diffuse)
{
    float3 d;
    AdditionalLightsLambert_float(WorldPos, WorldNormal, ScreenUV, d);
    Diffuse = d;
}
//#endregion

#endif
