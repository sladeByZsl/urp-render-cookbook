// 第 18 章公共函数：一个够用的“简易光照”，以及菲涅尔、哈希等小工具。（GLSL 版，对应 Ch18Common.hlsl）
// 本章重点是效果本身，光照只用主光 + 阴影 + 球谐环境光 + Blinn-Phong 高光，
// 完整 PBR 见第 10、11 章；需要时可以把 SimpleLighting 换成 UniversalFragmentPBR。
// Core.glsl / Lighting.glsl 已自动包含，这里不用再 include。
#ifndef COOKBOOK_CH18_COMMON_INCLUDED
#define COOKBOOK_CH18_COMMON_INCLUDED

//#region lighting
vec3 SimpleLighting(vec3 albedo, vec3 positionWS, vec3 normalWS, float smoothness)
{
    vec4 shadowCoord = TransformWorldToShadowCoord(positionWS);
    Light mainLight = GetMainLight(shadowCoord);
    vec3 viewWS = GetWorldSpaceNormalizeViewDir(positionWS);

    float NdotL = saturate(dot(normalWS, mainLight.direction));
    vec3 halfDir = SafeNormalize(mainLight.direction + viewWS);
    // 光滑度 0~1 映射到高光指数 2~2048，乘 smoothness 让粗糙表面的高光更暗
    float specPow = exp2(10.0 * smoothness + 1.0);
    float spec = pow(saturate(dot(normalWS, halfDir)), specPow) * smoothness * NdotL;

    float atten = mainLight.distanceAttenuation * mainLight.shadowAttenuation;
    vec3 direct = (albedo * NdotL + spec) * mainLight.color * atten;
    vec3 ambient = SampleSH(normalWS) * albedo;
    return direct + ambient;
}
//#endregion

//#region fresnel
// 经验菲涅尔：视线与法线越垂直（轮廓处）值越大。power 越大，亮边越窄。
float FresnelRim(vec3 normalWS, vec3 viewWS, float power)
{
    return pow(1.0 - saturate(dot(normalWS, viewWS)), power);
}
//#endregion

// 简单的 1D/2D 哈希，用来做闪烁、故障条等随机数
float Hash11(float p)
{
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

float Hash21(vec2 p)
{
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

#endif
