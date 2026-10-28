// MyPBR 的“只写深度”类 Pass：ShadowCaster / DepthOnly / DepthNormals
// 三者结构几乎一样：变换顶点、（可选）Alpha Clip，DepthNormals 额外输出世界法线。
#ifndef COOKBOOK_MYPBR_DEPTH_PASSES_INCLUDED
#define COOKBOOK_MYPBR_DEPTH_PASSES_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

struct DepthAttributes
{
    float4 positionOS : POSITION;
    float3 normalOS   : NORMAL;
    float4 tangentOS  : TANGENT;
    float2 texcoord   : TEXCOORD0;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct DepthVaryings
{
    float4 positionCS : SV_POSITION;
    float2 uv         : TEXCOORD0;
    half3  normalWS   : TEXCOORD1;
#if defined(_NORMALMAP)
    half4  tangentWS  : TEXCOORD2;
#endif
    UNITY_VERTEX_INPUT_INSTANCE_ID
    UNITY_VERTEX_OUTPUT_STEREO
};

void MyAlphaClip(float2 uv)
{
#if defined(_ALPHATEST_ON)
    half a = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uv).a * _BaseColor.a;
    clip(a - _Cutoff);
#endif
}

//#region shadow_caster
// URP 在渲染阴影图时设置这两个变量：方向光用 _LightDirection，点/聚光用 _LightPosition
float3 _LightDirection;
float3 _LightPosition;

DepthVaryings MyShadowVert(DepthAttributes input)
{
    DepthVaryings o = (DepthVaryings)0;
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_TRANSFER_INSTANCE_ID(input, o);

    float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
    float3 normalWS   = TransformObjectToWorldNormal(input.normalOS);
#if defined(_CASTING_PUNCTUAL_LIGHT_SHADOW)
    float3 lightDirWS = normalize(_LightPosition - positionWS);
#else
    float3 lightDirWS = _LightDirection;
#endif
    // 深度偏移 + 法线偏移（数值来自灯光的 Bias 设置），对抗 Shadow Acne
    float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirWS));
    // 把被近裁剪面切掉的投射体压到近平面上（Shadow Pancaking），否则阴影会出洞
#if UNITY_REVERSED_Z
    positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
#else
    positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
#endif
    o.positionCS = positionCS;
    o.uv = TRANSFORM_TEX(input.texcoord, _BaseMap);
    return o;
}

half4 MyShadowFrag(DepthVaryings i) : SV_Target
{
    UNITY_SETUP_INSTANCE_ID(i);
    MyAlphaClip(i.uv);
    return 0;
}
//#endregion

//#region depth_only
DepthVaryings MyDepthVert(DepthAttributes input)
{
    DepthVaryings o = (DepthVaryings)0;
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_TRANSFER_INSTANCE_ID(input, o);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
    o.positionCS = TransformObjectToHClip(input.positionOS.xyz);
    o.uv = TRANSFORM_TEX(input.texcoord, _BaseMap);
    return o;
}

half MyDepthFrag(DepthVaryings i) : SV_Target
{
    UNITY_SETUP_INSTANCE_ID(i);
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
    MyAlphaClip(i.uv);
    return i.positionCS.z;    // ColorMask R：部分平台把深度拷到颜色目标，写 z 即可
}
//#endregion

//#region depth_normals
DepthVaryings MyDepthNormalsVert(DepthAttributes input)
{
    DepthVaryings o = (DepthVaryings)0;
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_TRANSFER_INSTANCE_ID(input, o);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
    o.positionCS = TransformObjectToHClip(input.positionOS.xyz);
    o.uv = TRANSFORM_TEX(input.texcoord, _BaseMap);
    VertexNormalInputs nrm = GetVertexNormalInputs(input.normalOS, input.tangentOS);
    o.normalWS = nrm.normalWS;
#if defined(_NORMALMAP)
    o.tangentWS = half4(nrm.tangentWS, input.tangentOS.w * GetOddNegativeScale());
#endif
    return o;
}

void MyDepthNormalsFrag(DepthVaryings i
    , out half4 outNormalWS : SV_Target0
#if defined(_WRITE_RENDERING_LAYERS)
    , out float4 outRenderingLayers : SV_Target1
#endif
    )
{
    UNITY_SETUP_INSTANCE_ID(i);
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
    MyAlphaClip(i.uv);
#if defined(_NORMALMAP)
    // SSAO、贴花等读 _CameraNormalsTexture，带上法线贴图细节它们才对得上
    half3 normalTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, i.uv), _BumpScale);
    float3 bitangent = i.tangentWS.w * cross(i.normalWS, i.tangentWS.xyz);
    float3 normalWS = TransformTangentToWorld(normalTS, half3x3(i.tangentWS.xyz, bitangent, i.normalWS));
#else
    float3 normalWS = i.normalWS;
#endif
    outNormalWS = half4(NormalizeNormalPerPixel(normalWS), 0.0);   // URP 14 存未编码的世界法线
#if defined(_WRITE_RENDERING_LAYERS)
    outRenderingLayers = float4(EncodeMeshRenderingLayer(GetMeshRenderingLayer()), 0, 0, 0);
#endif
}
//#endregion

#endif
