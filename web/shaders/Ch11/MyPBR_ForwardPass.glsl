// MyPBR 的 UniversalForward Pass：顶点变换 + 准备 InputData + 调用 MyComputeLighting（GLSL 版，对应 Ch11/MyPBR_ForwardPass.hlsl）
#ifndef COOKBOOK_MYPBR_FORWARD_PASS_INCLUDED
#define COOKBOOK_MYPBR_FORWARD_PASS_INCLUDED

#include "Ch11/MyPBR_Lighting.glsl"

//#region structs
// WebGL 不允许结构体做 varying：HLSL 的 Varyings 拆成单独的变量（顶点输入 Attributes 由引擎固定命名：positionOS、normalOS……）
VARYING vec2  uv;
VARYING vec3  positionWS;
VARYING vec3  normalWS;
#if defined(_NORMALMAP)
VARYING vec4  tangentWS;      // xyz 切线，w 副切线符号
#endif
VARYING float fogFactor;
#if defined(_ADDITIONAL_LIGHTS_VERTEX)
VARYING vec3  vertexLight;
#endif
// 光照贴图 UV / 逐顶点 SH：网页版没有光照贴图，SH 在片元里逐像素求
//#endregion

//#region vert
#ifdef VERTEX
void MyPBRVert()
{
    VertexPositionInputs pos = GetVertexPositionInputs(positionOS.xyz);
    VertexNormalInputs   nrm = GetVertexNormalInputs(normalOS, tangentOS);

    gl_Position = pos.positionCS;
    positionWS  = pos.positionWS;
    uv          = TransformTex(texcoord0.xy, _BaseMap_ST);
    normalWS    = nrm.normalWS;
#if defined(_NORMALMAP)
    // 镜像缩放（负缩放）会翻转副切线方向，GetOddNegativeScale 负责修正
    tangentWS   = vec4(nrm.tangentWS, tangentOS.w * GetOddNegativeScale());
#endif
    fogFactor   = ComputeFogFactor(pos.positionCS.z);

#if defined(_ADDITIONAL_LIGHTS_VERTEX)
    // 逐顶点附加光：只累加 color * atten * NoL（漫反射的 E/π），镜面无法逐顶点
    vec3 vl = vec3(0.0);
    int n = GetAdditionalLightsCount();
    for (int i = 0; i < n; ++i)
    {
        Light l = GetAdditionalLight(i, pos.positionWS);
        vl += l.color * l.distanceAttenuation * saturate(dot(nrm.normalWS, l.direction));
    }
    vertexLight = vl;
#endif
}
#endif
//#endregion

#ifdef FRAGMENT
//#region input_data
// 填 URP 的 InputData：它只是“像素的几何与环境数据”的容器，
// 填好它，阴影、SSAO、附加光循环都能直接用
InputData MyInitInputData(vec3 normalTS)
{
    InputData d = InitInputData();
    d.positionWS = positionWS;
    d.positionCS = gl_FragCoord;
#if defined(_NORMALMAP)
    float sgn = tangentWS.w;
    vec3 bitangent = sgn * cross(normalWS, tangentWS.xyz);
    mat3 tbn = mat3(tangentWS.xyz, bitangent, normalWS);   // GLSL 的 mat3 按列构造：列就是 T/B/N
    d.tangentToWorld = tbn;
    d.normalWS = TransformTangentToWorld(normalTS, tbn);
#else
    d.normalWS = normalWS;
#endif
    d.normalWS = NormalizeNormalPerPixel(d.normalWS);   // 插值后长度不为 1，必须重新归一化
    d.viewDirectionWS = GetWorldSpaceNormalizeViewDir(positionWS);
    d.shadowCoord = TransformWorldToShadowCoord(positionWS);
    d.fogCoord = fogFactor;
#if defined(_ADDITIONAL_LIGHTS_VERTEX)
    d.vertexLighting = vertexLight;
#endif
    d.bakedGI = SampleSH(d.normalWS);                     // 网页版没有光照贴图：逐像素 SH
    d.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(gl_FragCoord);
    d.shadowMask = vec4(1.0);
    return d;
}
//#endregion

//#region frag
vec4 MyPBRFrag()
{
    MySurface s  = MySampleSurface(uv);
    InputData id = MyInitInputData(s.normalTS);
    MyMaterial m = MyInitMaterial(s.albedo, s.metallic, s.perceptualRoughness);

    // HLSL 版在 DEBUG_DISPLAY 下把表面参数交给 Rendering Debugger；网页版的调试视图见 Ch11/MyPBRDebug.glsl
    MyLightingTerms t = MyComputeLighting(s, m, id);
    vec3 color = t.directDiffuse + t.directSpecular + t.indirectDiffuse + t.indirectSpecular + t.emission;
    color = MixFog(color, id.fogCoord);
    return vec4(color, 1.0);
}
//#endregion
#endif

#endif
