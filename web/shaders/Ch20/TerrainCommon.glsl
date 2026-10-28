// 第 20 章公共函数：光照封装、三平面映射（Triplanar）、法线 Triplanar、高度混合（Height Blend）（GLSL 版，对应 Ch20/TerrainCommon.hlsl）
#ifndef COOKBOOK_CH20_TERRAIN_COMMON_INCLUDED
#define COOKBOOK_CH20_TERRAIN_COMMON_INCLUDED

//#region shade
// 把“世界空间位置 + 世界法线 + 表面参数”交给 URP 的 PBR 光照。
// 地形类 Shader 的表面是自己混出来的，不走 Lit 的 SurfaceInput，所以直接组装 InputData/SurfaceData。
// positionCS 在片元里传 gl_FragCoord（对应 HLSL 的 SV_POSITION）
vec4 Ch20ShadePBR(vec3 positionWS, vec3 normalWS, vec4 positionCS,
                  vec3 albedo, float metallic, float smoothness, float occlusion, float fogFactor)
{
    InputData inputData = InitInputData();
    inputData.positionWS = positionWS;
    inputData.positionCS = positionCS;
    inputData.normalWS = NormalizeNormalPerPixel(normalWS);
    inputData.viewDirectionWS = GetWorldSpaceNormalizeViewDir(positionWS);
    inputData.shadowCoord = TransformWorldToShadowCoord(positionWS);   // 逐像素算级联，避免顶点插值跨级联
    inputData.fogCoord = fogFactor;
    inputData.bakedGI = SampleSH(inputData.normalWS);
    inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(positionCS);  // Forward+ 的分块光源查找要用
    inputData.shadowMask = vec4(1, 1, 1, 1);

    SurfaceData surface = InitSurfaceData();
    surface.albedo = albedo;
    surface.metallic = metallic;
    surface.smoothness = smoothness;
    surface.occlusion = occlusion;
    surface.alpha = 1.0;
    surface.normalTS = vec3(0, 0, 1);

    vec4 color = UniversalFragmentPBR(inputData, surface);
    color.rgb = MixFog(color.rgb, fogFactor);
    return color;
}
//#endregion

//#region triplanar
// 三个投影方向的混合权重：|N| 的 sharpness 次方再归一化。
// sharpness 越大，过渡带越窄；1 时过渡最宽，45° 斜面上能看到两张图叠在一起。
vec3 TriplanarWeights(vec3 normalWS, float sharpness)
{
    vec3 w = pow(abs(normalWS), vec3(sharpness));
    return w / max(dot(w, vec3(1.0)), 1e-5);
}

struct TriplanarUV
{
    vec2 x;   // 沿 X 轴投影：用 (z, y)
    vec2 y;   // 沿 Y 轴投影：用 (x, z)
    vec2 z;   // 沿 Z 轴投影：用 (x, y)
};

// HLSL 的 normalWS < 0 ? -1.0 : 1.0（逐分量）
vec3 Ch20AxisSign(vec3 n) { return mix(vec3(1.0), vec3(-1.0), vec3(lessThan(n, vec3(0.0)))); }

TriplanarUV GetTriplanarUV(vec3 positionWS, vec3 normalWS, float scale)
{
    TriplanarUV t;
    vec3 p = positionWS * scale;
    t.x = p.zy;
    t.y = p.xz;
    t.z = p.xy;
    // 背面方向的投影会左右镜像（文字、箭头会反），按法线符号把 U 翻回来
    vec3 s = Ch20AxisSign(normalWS);
    t.x.x *= s.x;
    t.y.x *= s.y;
    t.z.x *= -s.z;
    return t;
}

// GLSL 的采样器可以直接当函数参数（对应 HLSL 的 TEXTURE2D_PARAM(tex, samp)）
vec4 SampleTriplanar(sampler2D tex, TriplanarUV uv, vec3 w)
{
    vec4 cx = texture(tex, uv.x);
    vec4 cy = texture(tex, uv.y);
    vec4 cz = texture(tex, uv.z);
    return cx * w.x + cy * w.y + cz * w.z;
}
//#endregion

// 桌面平台 URP 的 UnpackNormalScale 实际调用 UnpackNormalmapRGorAG（x 取 A×R、y 取 G、z 由 xy 重建）。
// 本章的岩石法线图按 DXT5nm 布局存成 (1, y, y, x)。这个函数在引擎 Core.glsl 里已有，与 URP 相同，这里直接用。

// Core RP（CommonMaterial.hlsl）的 BlendNormalRNM：把细节法线 n2 “旋转”到基底法线 n1 上
vec3 BlendNormalRNM(vec3 n1, vec3 n2)
{
    vec3 t = n1.xyz + vec3(0.0, 0.0, 1.0);
    vec3 u = n2.xyz * vec3(-1.0, -1.0, 1.0);
    vec3 r = (t / t.z) * dot(t, u) - u;
    return r;
}

//#region triplanarNormal
// 法线的 Triplanar：三张切线空间法线各自“转”到世界空间再按权重混合。
// mode 0 = 直接 swizzle（忽略几何法线，球会被照成方块）
// mode 1 = UDN（xy 相加，z 用几何法线）
// mode 2 = Whiteout（xy 相加，z 相乘）
// mode 3 = RNM（Reoriented Normal Mapping，把细节法线“旋转”到几何法线上）
vec3 TriplanarNormalWS(sampler2D bump, TriplanarUV uv, vec3 w, vec3 normalWS, float scale, int mode)
{
    vec3 tx = UnpackNormalmapRGorAG(texture(bump, uv.x), scale);
    vec3 ty = UnpackNormalmapRGorAG(texture(bump, uv.y), scale);
    vec3 tz = UnpackNormalmapRGorAG(texture(bump, uv.z), scale);

    vec3 axisSign = Ch20AxisSign(normalWS);
    // 与 GetTriplanarUV 中翻转 U 对应：切线 x 分量也要跟着翻
    tx.x *= axisSign.x;
    ty.x *= axisSign.y;
    tz.x *= -axisSign.z;

    vec3 n = normalWS;
    vec3 an = abs(normalWS);
    if (mode == 0)          // Swizzle：假设表面就是轴对齐的平面
    {
        tx.z *= axisSign.x; ty.z *= axisSign.y; tz.z *= axisSign.z;
    }
    else if (mode == 1)     // UDN
    {
        tx = vec3(tx.xy + n.zy, n.x);
        ty = vec3(ty.xy + n.xz, n.y);
        tz = vec3(tz.xy + n.xy, n.z);
    }
    else if (mode == 2)     // Whiteout
    {
        tx = vec3(tx.xy + n.zy, abs(tx.z) * n.x);
        ty = vec3(ty.xy + n.xz, abs(ty.z) * n.y);
        tz = vec3(tz.xy + n.xy, abs(tz.z) * n.z);
    }
    else                    // RNM：基底法线取 (各平面内的几何法线, |N|)，用 core 库的 BlendNormalRNM
    {
        tx = BlendNormalRNM(vec3(n.zy, an.x), tx);
        ty = BlendNormalRNM(vec3(n.xz, an.y), ty);
        tz = BlendNormalRNM(vec3(n.xy, an.z), tz);
        tx.z *= axisSign.x; ty.z *= axisSign.y; tz.z *= axisSign.z;
    }
    // swizzle 回世界轴：X 平面的 (u,v,n) = (z,y,x)，Y 平面 = (x,z,y)，Z 平面 = (x,y,z)
    return normalize(tx.zyx * w.x + ty.xzy * w.y + tz.xyz * w.z);
}
//#endregion

//#region heightBlend
// 高度混合：t 是“第二层的遮罩权重”，h1/h2 是两层的高度（存在贴图 A 通道）。
// 谁“又高、权重又大”谁就露出来；depth 控制过渡软硬（0.01 很硬，0.3 接近线性）。
float HeightBlendWeight(float h1, float h2, float t, float depth)
{
    float a1 = h1 + (1.0 - t);
    float a2 = h2 + t;
    float top = max(a1, a2) - depth;
    float b1 = max(a1 - top, 0.0);
    float b2 = max(a2 - top, 0.0);
    return b2 / max(b1 + b2, 1e-4);
}
//#endregion

#endif
