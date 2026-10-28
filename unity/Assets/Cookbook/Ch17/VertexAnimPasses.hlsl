// 三个 Pass 的顶点函数。包含本文件之前必须已经定义 void Deform(inout VAAttributes v)。
// 如果阴影里需要不同的变形（例如做对比实验），可以先 #define VA_DEFORM_SHADOW 另一个函数名。
#ifndef COOKBOOK_CH17_VA_PASSES_INCLUDED
#define COOKBOOK_CH17_VA_PASSES_INCLUDED

#ifndef VA_DEFORM_SHADOW
    #define VA_DEFORM_SHADOW Deform
#endif

//#region passes
VAVaryings VAForwardVert(VAAttributes v)
{
    Deform(v);                                           // ① 颜色 Pass：变形
    VAVaryings o;
    o.positionWS = TransformObjectToWorld(v.positionOS.xyz);
    o.positionCS = TransformWorldToHClip(o.positionWS);
    o.normalWS   = TransformObjectToWorldNormal(v.normalOS);
    o.uv = v.uv; o.color = v.color; o.extra = v.uv2;
    return o;
}

float4 VAShadowVert(VAAttributes v) : SV_POSITION
{
    VA_DEFORM_SHADOW(v);                                 // ② 阴影 Pass：同样的变形
    float3 positionWS = TransformObjectToWorld(v.positionOS.xyz);
    float3 normalWS = TransformObjectToWorldNormal(v.normalOS);
    float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, _LightDirection));
#if UNITY_REVERSED_Z
    positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
#else
    positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
#endif
    return positionCS;
}

float4 VADepthVert(VAAttributes v) : SV_POSITION
{
    Deform(v);                                           // ③ 深度 Pass：同样的变形
    return TransformObjectToHClip(v.positionOS.xyz);
}
//#endregion

half4 VANullFrag() : SV_Target { return 0; }

#endif
