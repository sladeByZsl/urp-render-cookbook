// 视差映射三件套：Steep Parallax、Parallax Occlusion Mapping（POM）、视差自阴影。
// 约定：高度图 1 = 表面最高处（与多边形平面重合），0 = 最深处；depth = 1 - height。
// viewDirTS / lightDirTS 都是“从表面指向外”的切线空间单位向量（z > 0 表示在表面上方）。
#ifndef COOKBOOK_CH07_PARALLAX_INCLUDED
#define COOKBOOK_CH07_PARALLAX_INCLUDED

#define CH07_MAX_STEPS 64   // 循环上限，防止极端掠射角时步数失控

// 循环里不能用普通的 SAMPLE_TEXTURE2D：隐式求导在动态分支/循环中无定义，
// 所以先在循环外算好 ddx/ddy，循环里用 SAMPLE_TEXTURE2D_GRAD。
#define CH07_DEPTH(uv) (1.0 - SAMPLE_TEXTURE2D_GRAD(heightMap, sampler_heightMap, uv, dx, dy).r)

//#region steep
// 陡峭视差（Steep Parallax）：把 [0,1] 深度切成 numLayers 层，沿视线一层层往里走，
// 直到“视线深度”第一次超过“高度图深度”。返回命中点 UV；hitDepth 输出命中深度。
float2 SteepParallax(TEXTURE2D_PARAM(heightMap, sampler_heightMap), float2 uv, half3 viewDirTS,
                     float scale, float minLayers, float maxLayers, out float hitDepth)
{
    float2 dx = ddx(uv), dy = ddy(uv);
    // 正视时层数少，掠射时层数多：掠射时每层在 UV 上走得更远，需要更细的步长
    float numLayers = lerp(maxLayers, minLayers, saturate(viewDirTS.z));
    float layerDepth = 1.0 / numLayers;
    // 视线每深入 1 个单位，UV 偏移 V.xy / V.z * scale（相似三角形）；方向与视线相反
    float2 deltaUV = viewDirTS.xy / max(viewDirTS.z, 0.05) * scale / numLayers;

    float rayDepth = 0;
    float mapDepth = CH07_DEPTH(uv);
    [loop] for (int i = 0; i < CH07_MAX_STEPS && rayDepth < mapDepth; i++)
    {
        uv -= deltaUV;
        mapDepth = CH07_DEPTH(uv);
        rayDepth += layerDepth;
    }
    hitDepth = rayDepth;
    return uv;
}
//#endregion

//#region pom
// 视差遮挡映射（POM）：在 Steep 的基础上，对“穿过表面前后”的两层做一次线性插值，
// 把台阶状的命中点修正到两层之间，低层数也能得到平滑结果。
float2 ParallaxOcclusion(TEXTURE2D_PARAM(heightMap, sampler_heightMap), float2 uv, half3 viewDirTS,
                         float scale, float minLayers, float maxLayers, out float hitDepth)
{
    float2 dx = ddx(uv), dy = ddy(uv);
    float numLayers = lerp(maxLayers, minLayers, saturate(viewDirTS.z));
    float layerDepth = 1.0 / numLayers;
    float2 deltaUV = viewDirTS.xy / max(viewDirTS.z, 0.05) * scale / numLayers;

    float rayDepth = 0;
    float mapDepth = CH07_DEPTH(uv);
    [loop] for (int i = 0; i < CH07_MAX_STEPS && rayDepth < mapDepth; i++)
    {
        uv -= deltaUV;
        mapDepth = CH07_DEPTH(uv);
        rayDepth += layerDepth;
    }

    // 穿透后（after）与穿透前（before）两层，各自“视线深度 - 高度图深度”的差
    float2 prevUV = uv + deltaUV;
    float after  = mapDepth - rayDepth;                              // ≤ 0
    float before = CH07_DEPTH(prevUV) - (rayDepth - layerDepth);     // ≥ 0
    float w = after / (after - before + 1e-5);                       // 两段直线的交点比例
    hitDepth = lerp(rayDepth, rayDepth - layerDepth, w);
    return lerp(uv, prevUV, w);
}
//#endregion

//#region shadow
// 视差自阴影：从命中点朝灯光方向往上走，检查途中有没有更高的凸起挡住光。
// 返回 1 = 不在阴影里，0 = 完全遮挡。用“挡了多少 × 离起点多近”做软化。
// dx/dy 传入原始 UV 的导数：偏移后的 UV 在台阶边缘不连续，用它求导会选错 mip。
half ParallaxSelfShadow(TEXTURE2D_PARAM(heightMap, sampler_heightMap), float2 uv, float2 dx, float2 dy,
                        float hitDepth, half3 lightDirTS, float scale, float steps, float softness)
{
    if (lightDirTS.z <= 0) return 0;           // 灯在表面背面
    if (hitDepth <= 0.001) return 1;           // 已经在最高处，没有东西能挡它

    float layerDepth = hitDepth / steps;       // 只需要从命中深度走回表面
    float2 deltaUV = lightDirTS.xy / max(lightDirTS.z, 0.05) * scale * layerDepth;

    float rayDepth = hitDepth;
    float occlusion = 0;
    [loop] for (int i = 1; i <= (int)steps && i <= CH07_MAX_STEPS; i++)
    {
        uv += deltaUV;
        rayDepth -= layerDepth;
        float mapDepth = CH07_DEPTH(uv);
        // mapDepth < rayDepth：这里的表面比光线还高 → 光线被挡
        float o = (rayDepth - mapDepth) * softness * (1.0 - (i - 1) / steps);
        occlusion = max(occlusion, o);
    }
    return 1.0 - saturate(occlusion);
}
//#endregion

#endif
