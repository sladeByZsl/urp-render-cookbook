// 第 20 章公共函数：光照封装、三平面映射（Triplanar）、法线 Triplanar、高度混合（Height Blend）
#ifndef COOKBOOK_CH20_TERRAIN_COMMON_INCLUDED
#define COOKBOOK_CH20_TERRAIN_COMMON_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

//#region shade
// 把“世界空间位置 + 世界法线 + 表面参数”交给 URP 的 PBR 光照。
// 地形类 Shader 的表面是自己混出来的，不走 Lit 的 SurfaceInput，所以直接组装 InputData/SurfaceData。
half4 Ch20ShadePBR(float3 positionWS, half3 normalWS, float4 positionCS,
                   half3 albedo, half metallic, half smoothness, half occlusion, half fogFactor)
{
    InputData inputData = (InputData)0;
    inputData.positionWS = positionWS;
    inputData.normalWS = NormalizeNormalPerPixel(normalWS);
    inputData.viewDirectionWS = GetWorldSpaceNormalizeViewDir(positionWS);
    inputData.shadowCoord = TransformWorldToShadowCoord(positionWS);   // 逐像素算级联，避免顶点插值跨级联
    inputData.fogCoord = fogFactor;
    inputData.bakedGI = SampleSH(inputData.normalWS);
    inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(positionCS);  // Forward+ 的分块光源查找要用
    inputData.shadowMask = half4(1, 1, 1, 1);

    SurfaceData surface = (SurfaceData)0;
    surface.albedo = albedo;
    surface.metallic = metallic;
    surface.smoothness = smoothness;
    surface.occlusion = occlusion;
    surface.alpha = 1;
    surface.normalTS = half3(0, 0, 1);

    half4 color = UniversalFragmentPBR(inputData, surface);
    color.rgb = MixFog(color.rgb, fogFactor);
    return color;
}
//#endregion

//#region triplanar
// 三个投影方向的混合权重：|N| 的 sharpness 次方再归一化。
// sharpness 越大，过渡带越窄；1 时过渡最宽，45° 斜面上能看到两张图叠在一起。
float3 TriplanarWeights(float3 normalWS, float sharpness)
{
    float3 w = pow(abs(normalWS), sharpness);
    return w / max(dot(w, 1.0), 1e-5);
}

struct TriplanarUV
{
    float2 x;   // 沿 X 轴投影：用 (z, y)
    float2 y;   // 沿 Y 轴投影：用 (x, z)
    float2 z;   // 沿 Z 轴投影：用 (x, y)
};

TriplanarUV GetTriplanarUV(float3 positionWS, float3 normalWS, float scale)
{
    TriplanarUV t;
    float3 p = positionWS * scale;
    t.x = p.zy;
    t.y = p.xz;
    t.z = p.xy;
    // 背面方向的投影会左右镜像（文字、箭头会反），按法线符号把 U 翻回来
    float3 s = normalWS < 0 ? -1.0 : 1.0;
    t.x.x *= s.x;
    t.y.x *= s.y;
    t.z.x *= -s.z;
    return t;
}

half4 SampleTriplanar(TEXTURE2D_PARAM(tex, samp), TriplanarUV uv, float3 w)
{
    half4 cx = SAMPLE_TEXTURE2D(tex, samp, uv.x);
    half4 cy = SAMPLE_TEXTURE2D(tex, samp, uv.y);
    half4 cz = SAMPLE_TEXTURE2D(tex, samp, uv.z);
    return cx * w.x + cy * w.y + cz * w.z;
}
//#endregion

//#region triplanarNormal
// 法线的 Triplanar：三张切线空间法线各自“转”到世界空间再按权重混合。
// mode 0 = 直接 swizzle（忽略几何法线，球会被照成方块）
// mode 1 = UDN（xy 相加，z 用几何法线）
// mode 2 = Whiteout（xy 相加，z 相乘）
// mode 3 = RNM（Reoriented Normal Mapping，把细节法线“旋转”到几何法线上）
half3 TriplanarNormalWS(TEXTURE2D_PARAM(bump, samp), TriplanarUV uv, float3 w, half3 normalWS, half scale, int mode)
{
    half3 tx = UnpackNormalScale(SAMPLE_TEXTURE2D(bump, samp, uv.x), scale);
    half3 ty = UnpackNormalScale(SAMPLE_TEXTURE2D(bump, samp, uv.y), scale);
    half3 tz = UnpackNormalScale(SAMPLE_TEXTURE2D(bump, samp, uv.z), scale);

    half3 axisSign = normalWS < 0 ? -1.0 : 1.0;
    // 与 GetTriplanarUV 中翻转 U 对应：切线 x 分量也要跟着翻
    tx.x *= axisSign.x;
    ty.x *= axisSign.y;
    tz.x *= -axisSign.z;

    half3 n = normalWS;
    half3 an = abs(normalWS);
    if (mode == 0)          // Swizzle：假设表面就是轴对齐的平面
    {
        tx.z *= axisSign.x; ty.z *= axisSign.y; tz.z *= axisSign.z;
    }
    else if (mode == 1)     // UDN
    {
        tx = half3(tx.xy + n.zy, n.x);
        ty = half3(ty.xy + n.xz, n.y);
        tz = half3(tz.xy + n.xy, n.z);
    }
    else if (mode == 2)     // Whiteout
    {
        tx = half3(tx.xy + n.zy, abs(tx.z) * n.x);
        ty = half3(ty.xy + n.xz, abs(ty.z) * n.y);
        tz = half3(tz.xy + n.xy, abs(tz.z) * n.z);
    }
    else                    // RNM：基底法线取 (各平面内的几何法线, |N|)，用 core 库的 BlendNormalRNM
    {
        tx = BlendNormalRNM(half3(n.zy, an.x), tx);
        ty = BlendNormalRNM(half3(n.xz, an.y), ty);
        tz = BlendNormalRNM(half3(n.xy, an.z), tz);
        tx.z *= axisSign.x; ty.z *= axisSign.y; tz.z *= axisSign.z;
    }
    // swizzle 回世界轴：X 平面的 (u,v,n) = (z,y,x)，Y 平面 = (x,z,y)，Z 平面 = (x,y,z)
    return normalize(tx.zyx * w.x + ty.xzy * w.y + tz.xyz * w.z);
}
//#endregion

//#region heightBlend
// 高度混合：t 是“第二层的遮罩权重”，h1/h2 是两层的高度（存在贴图 A 通道）。
// 谁“又高、权重又大”谁就露出来；depth 控制过渡软硬（0.01 很硬，0.3 接近线性）。
half HeightBlendWeight(half h1, half h2, half t, half depth)
{
    half a1 = h1 + (1.0 - t);
    half a2 = h2 + t;
    half top = max(a1, a2) - depth;
    half b1 = max(a1 - top, 0.0);
    half b2 = max(a2 - top, 0.0);
    return b2 / max(b1 + b2, 1e-4);
}
//#endregion

#endif
