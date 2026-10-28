// MyPBR 的 UniversalForward Pass：顶点变换 + 准备 InputData + 调用 MyComputeLighting
#ifndef COOKBOOK_MYPBR_FORWARD_PASS_INCLUDED
#define COOKBOOK_MYPBR_FORWARD_PASS_INCLUDED

#include "Assets/Cookbook/Ch11/MyPBR_Lighting.hlsl"

//#region structs
struct Attributes
{
    float4 positionOS        : POSITION;
    float3 normalOS          : NORMAL;
    float4 tangentOS         : TANGENT;
    float2 texcoord          : TEXCOORD0;
    float2 staticLightmapUV  : TEXCOORD1;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct Varyings
{
    float4 positionCS  : SV_POSITION;
    float2 uv          : TEXCOORD0;
    float3 positionWS  : TEXCOORD1;
    half3  normalWS    : TEXCOORD2;
#if defined(_NORMALMAP)
    half4  tangentWS   : TEXCOORD3;    // xyz 切线，w 副切线符号
#endif
    half   fogFactor   : TEXCOORD4;
#if defined(_ADDITIONAL_LIGHTS_VERTEX)
    half3  vertexLight : TEXCOORD5;
#endif
    DECLARE_LIGHTMAP_OR_SH(staticLightmapUV, vertexSH, 6);   // 有光照贴图时是 lightmap UV，否则是逐顶点 SH
    UNITY_VERTEX_INPUT_INSTANCE_ID
    UNITY_VERTEX_OUTPUT_STEREO
};
//#endregion

//#region vert
Varyings MyPBRVert(Attributes input)
{
    Varyings o = (Varyings)0;
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_TRANSFER_INSTANCE_ID(input, o);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

    VertexPositionInputs pos = GetVertexPositionInputs(input.positionOS.xyz);
    VertexNormalInputs   nrm = GetVertexNormalInputs(input.normalOS, input.tangentOS);

    o.positionCS = pos.positionCS;
    o.positionWS = pos.positionWS;
    o.uv         = TRANSFORM_TEX(input.texcoord, _BaseMap);
    o.normalWS   = nrm.normalWS;
#if defined(_NORMALMAP)
    // 镜像缩放（负缩放）会翻转副切线方向，GetOddNegativeScale 负责修正
    o.tangentWS  = half4(nrm.tangentWS, input.tangentOS.w * GetOddNegativeScale());
#endif
    o.fogFactor  = ComputeFogFactor(pos.positionCS.z);

#if defined(_ADDITIONAL_LIGHTS_VERTEX)
    // 逐顶点附加光：只累加 color * atten * NoL（漫反射的 E/π），镜面无法逐顶点
    half3 vl = 0;
    uint n = GetAdditionalLightsCount();
    for (uint i = 0u; i < n; ++i)
    {
        Light l = GetAdditionalLight(i, pos.positionWS);
        vl += l.color * l.distanceAttenuation * saturate(dot(nrm.normalWS, l.direction));
    }
    o.vertexLight = vl;
#endif

    OUTPUT_LIGHTMAP_UV(input.staticLightmapUV, unity_LightmapST, o.staticLightmapUV);
    OUTPUT_SH(o.normalWS, o.vertexSH);
    return o;
}
//#endregion

//#region input_data
// 填 URP 的 InputData：它只是“像素的几何与环境数据”的容器，
// 填好它，阴影、SSAO、Forward+ 的分簇循环、Rendering Debugger 都能直接用
InputData MyInitInputData(Varyings i, half3 normalTS)
{
    InputData d = (InputData)0;
    d.positionWS = i.positionWS;
    d.positionCS = i.positionCS;
#if defined(_NORMALMAP)
    float  sgn = i.tangentWS.w;
    float3 bitangent = sgn * cross(i.normalWS, i.tangentWS.xyz);
    half3x3 tbn = half3x3(i.tangentWS.xyz, bitangent, i.normalWS);
    d.tangentToWorld = tbn;
    d.normalWS = TransformTangentToWorld(normalTS, tbn);
#else
    d.normalWS = i.normalWS;
#endif
    d.normalWS = NormalizeNormalPerPixel(d.normalWS);   // 插值后长度不为 1，必须重新归一化
    d.viewDirectionWS = GetWorldSpaceNormalizeViewDir(i.positionWS);
    d.shadowCoord = TransformWorldToShadowCoord(i.positionWS); // 逐像素算级联索引，级联/屏幕空间阴影都适用
    d.fogCoord = InitializeInputDataFog(float4(i.positionWS, 1.0), i.fogFactor);
#if defined(_ADDITIONAL_LIGHTS_VERTEX)
    d.vertexLighting = i.vertexLight;
#endif
    d.bakedGI = SAMPLE_GI(i.staticLightmapUV, i.vertexSH, d.normalWS);   // 光照贴图或 SH
    d.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(i.positionCS);
    d.shadowMask = SAMPLE_SHADOWMASK(i.staticLightmapUV);
#if defined(DEBUG_DISPLAY)
    #if defined(LIGHTMAP_ON)
    d.staticLightmapUV = i.staticLightmapUV;
    #else
    d.vertexSH = i.vertexSH;
    #endif
#endif
    return d;
}
//#endregion

//#region frag
half4 MyPBRFrag(Varyings i
#if defined(_WRITE_RENDERING_LAYERS)
    , out float4 outRenderingLayers : SV_Target1
#endif
    ) : SV_Target0
{
    UNITY_SETUP_INSTANCE_ID(i);
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

    MySurface s  = MySampleSurface(i.uv);
    InputData id = MyInitInputData(i, s.normalTS);
    MyMaterial m = MyInitMaterial(s.albedo, s.metallic, s.perceptualRoughness);

#if defined(DEBUG_DISPLAY)
    // 让 Rendering Debugger 的材质视图 / 材质校验也能作用于 MyPBR：
    // 把我们的表面参数翻译成 URP 的 SurfaceData，交给它的调试函数
    SurfaceData sd = (SurfaceData)0;
    sd.albedo = s.albedo;  sd.metallic = s.metallic;  sd.specular = m.f0;
    sd.smoothness = 1.0h - s.perceptualRoughness;     sd.normalTS = s.normalTS;
    sd.emission = s.emission;  sd.occlusion = s.occlusion;  sd.alpha = s.alpha;
    id.brdfDiffuse = m.diffuseColor;  id.brdfSpecular = m.f0;
    half4 debugColor;
    if (CanDebugOverrideOutputColor(id, sd, debugColor))
        return debugColor;
#endif

    MyLightingTerms t = MyComputeLighting(s, m, id);
    float3 color = t.directDiffuse + t.directSpecular + t.indirectDiffuse + t.indirectSpecular + t.emission;
    color = MixFog(color, id.fogCoord);

#if defined(_WRITE_RENDERING_LAYERS)
    outRenderingLayers = float4(EncodeMeshRenderingLayer(GetMeshRenderingLayer()), 0, 0, 0);
#endif
    return half4(color, 1.0);
}
//#endregion

#endif
