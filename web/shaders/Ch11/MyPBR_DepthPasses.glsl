// MyPBR 的“只写深度”类 Pass：ShadowCaster / DepthOnly / DepthNormals（GLSL 版，对应 Ch11/MyPBR_DepthPasses.hlsl）
// 三者结构几乎一样：变换顶点、（可选）Alpha Clip，DepthNormals 额外输出世界法线。
// 使用前定义 MY_SHADOW_PASS / MY_DEPTH_PASS / MY_DEPTH_NORMALS_PASS 之一，选择本 Pass 的顶点/片元函数。
#ifndef COOKBOOK_MYPBR_DEPTH_PASSES_INCLUDED
#define COOKBOOK_MYPBR_DEPTH_PASSES_INCLUDED

// DepthVaryings：WebGL 不允许结构体做 varying，拆成单独的变量
VARYING vec2 uv;
VARYING vec3 normalWS;
#if defined(_NORMALMAP)
VARYING vec4 tangentWS;
#endif

#ifdef FRAGMENT
void MyAlphaClip(vec2 uv)
{
#if defined(_ALPHATEST_ON)
    float a = texture(_BaseMap, uv).a * _BaseColor.a;
    if (a - _Cutoff < 0.0) discard;
#endif
}
#endif

//#region shadow_caster
// URP 在渲染阴影图时设置这两个变量：方向光用 _LightDirection，点/聚光用 _LightPosition
// （网页版核心库 Lighting.glsl 已声明 _LightDirection、_LightPosition、_CastingPunctualLightShadow）
#ifdef VERTEX
void MyShadowVert()
{
    vec3 positionWS = TransformObjectToWorld(positionOS.xyz);
    vec3 nWS        = TransformObjectToWorldNormal(normalOS);
    // HLSL 里是 _CASTING_PUNCTUAL_LIGHT_SHADOW 关键字；网页版是 uniform
    vec3 lightDirWS = _CastingPunctualLightShadow > 0.5 ? normalize(_LightPosition - positionWS) : _LightDirection;
    // 深度偏移 + 法线偏移（数值来自灯光的 Bias 设置），对抗 Shadow Acne
    vec4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, nWS, lightDirWS));
    // 把被近裁剪面切掉的投射体压到近平面上（Shadow Pancaking），否则阴影会出洞
#if UNITY_REVERSED_Z
    positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
#else
    positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE * positionCS.w);   // GL 的近平面在 z = -w
#endif
    gl_Position = positionCS;
    uv = TransformTex(texcoord0.xy, _BaseMap_ST);
}
#endif

#ifdef FRAGMENT
vec4 MyShadowFrag()
{
    MyAlphaClip(uv);
    return vec4(0.0);
}
#endif
//#endregion

//#region depth_only
#ifdef VERTEX
void MyDepthVert()
{
    gl_Position = TransformObjectToHClip(positionOS.xyz);
    uv = TransformTex(texcoord0.xy, _BaseMap_ST);
}
#endif

#ifdef FRAGMENT
vec4 MyDepthFrag()
{
    MyAlphaClip(uv);
    return vec4(gl_FragCoord.z);    // ColorMask R：部分平台把深度拷到颜色目标，写 z 即可
}
#endif
//#endregion

//#region depth_normals
#ifdef VERTEX
void MyDepthNormalsVert()
{
    gl_Position = TransformObjectToHClip(positionOS.xyz);
    uv = TransformTex(texcoord0.xy, _BaseMap_ST);
    VertexNormalInputs nrm = GetVertexNormalInputs(normalOS, tangentOS);
    normalWS = nrm.normalWS;
#if defined(_NORMALMAP)
    tangentWS = vec4(nrm.tangentWS, tangentOS.w * GetOddNegativeScale());
#endif
}
#endif

#ifdef FRAGMENT
vec4 MyDepthNormalsFrag()
{
    MyAlphaClip(uv);
#if defined(_NORMALMAP)
    // SSAO、贴花等读 _CameraNormalsTexture，带上法线贴图细节它们才对得上
    vec3 normalTS = UnpackNormalScale(texture(_BumpMap, uv), _BumpScale);
    vec3 bitangent = tangentWS.w * cross(normalWS, tangentWS.xyz);
    vec3 n = TransformTangentToWorld(normalTS, mat3(tangentWS.xyz, bitangent, normalWS));
#else
    vec3 n = normalWS;
#endif
    return vec4(NormalizeNormalPerPixel(n), 0.0);   // URP 14 存未编码的世界法线
}
#endif
//#endregion

#endif
