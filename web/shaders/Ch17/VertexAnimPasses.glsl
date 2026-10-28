// 三个 Pass 的顶点函数。（GLSL 版，对应 Ch17/VertexAnimPasses.hlsl）
// 包含本文件之前必须已经定义 void Deform(inout VAAttributes v)。
// 如果阴影里需要不同的变形（例如做对比实验），可以先 #define VA_DEFORM_SHADOW 另一个函数名。
#ifndef COOKBOOK_CH17_VA_PASSES_INCLUDED
#define COOKBOOK_CH17_VA_PASSES_INCLUDED

#ifndef VA_DEFORM_SHADOW
    #define VA_DEFORM_SHADOW Deform
#endif

#ifdef VERTEX
//#region passes
void VAForwardVert()
{
    VAAttributes v = VAGetAttributes();
    Deform(v);                                           // ① 颜色 Pass：变形
    positionWS  = TransformObjectToWorld(v.positionOS.xyz);
    gl_Position = TransformWorldToHClip(positionWS);
    normalWS    = TransformObjectToWorldNormal(v.normalOS);
    uv = v.uv; vertColor = v.color; extra = v.uv2;
}

void VAShadowVert()
{
    VAAttributes v = VAGetAttributes();
    VA_DEFORM_SHADOW(v);                                 // ② 阴影 Pass：同样的变形
    vec3 posWS = TransformObjectToWorld(v.positionOS.xyz);
    vec3 nrmWS = TransformObjectToWorldNormal(v.normalOS);
    vec4 positionCS = TransformWorldToHClip(ApplyShadowBias(posWS, nrmWS, _LightDirection));
#if UNITY_REVERSED_Z
    positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
#else
    positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE * positionCS.w);
#endif
    gl_Position = positionCS;
}

void VADepthVert()
{
    VAAttributes v = VAGetAttributes();
    Deform(v);                                           // ③ 深度 Pass：同样的变形
    gl_Position = TransformObjectToHClip(v.positionOS.xyz);
}
//#endregion
#endif

#ifdef FRAGMENT
void VANullFrag() { fragColor = vec4(gl_FragCoord.z); }
#endif

#endif
