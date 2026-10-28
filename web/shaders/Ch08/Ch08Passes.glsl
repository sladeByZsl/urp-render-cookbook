// 第 8 章公用的辅助 Pass：ShadowCaster / DepthOnly / DepthNormals（GLSL 版，对应 Ch08Passes.hlsl）。
// 只依赖顶点位置和法线（不做 Alpha Clip），各 Shader 在 GLSLINCLUDE 里声明好材质 uniform 后再引用本文件。
// 用法：在 Pass 的 GLSLPROGRAM 里 #include 本文件，再在 main() 里调用对应的函数（HLSL 版是 #pragma vertex Ch08ShadowVert）。
// _LightDirection / _LightPosition / ApplyShadowBias 在自动包含的 Lighting.glsl 里已经声明。
#ifndef COOKBOOK_CH08_PASSES_INCLUDED
#define COOKBOOK_CH08_PASSES_INCLUDED

#ifdef CH08_DEPTH_NORMALS
VARYING vec3 ch08NormalWS;      // Ch08NormalVaryings.normalWS
#endif

#ifdef VERTEX
vec4 Ch08ShadowVert()
{
    vec3 positionWS = TransformObjectToWorld(positionOS.xyz);
    vec3 normalWS = TransformObjectToWorldNormal(normalOS);
    // _CASTING_PUNCTUAL_LIGHT_SHADOW 在 GLSL 版里是个 uniform
    vec3 lightDirectionWS = _CastingPunctualLightShadow > 0.5 ? normalize(_LightPosition - positionWS) : _LightDirection;
    vec4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS));
    // WebGL 深度不反转（UNITY_REVERSED_Z = 0），走 #else 分支：把近平面之前的投影物压到近平面上
    positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE * positionCS.w);
    return positionCS;
}

vec4 Ch08DepthVert()
{
    return TransformObjectToHClip(positionOS.xyz);
}

#ifdef CH08_DEPTH_NORMALS
// DepthNormals：SSAO、屏幕空间贴花等需要 _CameraNormalsTexture，没有这个 Pass 的物体在 SSAO 里是“隐形”的
vec4 Ch08DepthNormalsVert()
{
    ch08NormalWS = TransformObjectToWorldNormal(normalOS);
    return TransformObjectToHClip(positionOS.xyz);
}
#endif
#endif

#ifdef FRAGMENT
vec4 Ch08NullFrag()
{
    // Unity 的深度来自深度缓冲，返回 0 即可；网页版的 DepthOnly 与 URP 的 DepthOnlyPass 一致，把深度写进 R 通道
    return vec4(gl_FragCoord.z);
}

#ifdef CH08_DEPTH_NORMALS
vec4 Ch08DepthNormalsFrag()
{
    return vec4(NormalizeNormalPerPixel(ch08NormalWS), 0.0);
}
#endif
#endif

#endif
