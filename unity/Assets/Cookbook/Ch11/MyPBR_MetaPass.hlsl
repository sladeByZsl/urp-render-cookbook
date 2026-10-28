// MyPBR 的 Meta Pass：只在烘焙光照贴图时使用。
// 烘焙器把物体按 lightmap UV 摊平渲染，读两样东西：反照率（决定反弹光颜色）和自发光（作为光源参与烘焙）
#ifndef COOKBOOK_MYPBR_META_PASS_INCLUDED
#define COOKBOOK_MYPBR_META_PASS_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/MetaInput.hlsl"
#include "Assets/Cookbook/Ch11/MyPBR_BRDF.hlsl"

struct MetaAttributes
{
    float4 positionOS : POSITION;
    float2 uv0        : TEXCOORD0;
    float2 uv1        : TEXCOORD1;   // 静态光照贴图 UV
    float2 uv2        : TEXCOORD2;   // 动态（实时 GI）光照贴图 UV
};

struct MetaVaryings
{
    float4 positionCS : SV_POSITION;
    float2 uv         : TEXCOORD0;
#if defined(EDITOR_VISUALIZATION)
    float2 VizUV      : TEXCOORD1;
    float4 LightCoord : TEXCOORD2;
#endif
};

//#region meta
MetaVaryings MyMetaVert(MetaAttributes input)
{
    MetaVaryings o = (MetaVaryings)0;
    // 烘焙时 unity_MetaVertexControl 指示用哪套 UV 当“屏幕位置”
    o.positionCS = UnityMetaVertexPosition(input.positionOS.xyz, input.uv1, input.uv2);
    o.uv = TRANSFORM_TEX(input.uv0, _BaseMap);
#if defined(EDITOR_VISUALIZATION)
    UnityEditorVizData(input.positionOS.xyz, input.uv0, input.uv1, input.uv2, o.VizUV, o.LightCoord);
#endif
    return o;
}

half4 MyMetaFrag(MetaVaryings i) : SV_Target
{
    MySurface s = MySampleSurface(i.uv);
    MyMaterial m = MyInitMaterial(s.albedo, s.metallic, s.perceptualRoughness);

    UnityMetaInput meta = (UnityMetaInput)0;
    // 反弹光的颜色：漫反射色为主；粗糙金属的镜面反射在烘焙器看来也像“漫反射”，
    // 按粗糙度加一部分 F0 进去（与 URP Lit 的经验做法相同）
    meta.Albedo = m.diffuseColor + m.f0 * (m.perceptualRoughness * m.perceptualRoughness) * 0.5;
    meta.Emission = s.emission;
#if defined(EDITOR_VISUALIZATION)
    meta.VizUV = i.VizUV;
    meta.LightCoord = i.LightCoord;
#endif
    return UnityMetaFragment(meta);
}
//#endregion

#endif
