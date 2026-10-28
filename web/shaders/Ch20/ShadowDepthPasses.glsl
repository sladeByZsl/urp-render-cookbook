// 第 20 章地形 Shader 共用的 ShadowCaster / DepthOnly / DepthNormals 顶点与片元函数（无顶点变形、无 Alpha 裁剪）
// GLSL 版（对应 Ch20/ShadowDepthPasses.hlsl）。用法：在 Pass 的 GLSLPROGRAM 里先
//   #define CH20_SHADOW_PASS / CH20_DEPTH_PASS / CH20_DEPTHNORMALS_PASS 之一，再 #include 本文件。
// _LightDirection / _LightPosition 已在引擎的 Lighting.glsl 里声明；
// _CASTING_PUNCTUAL_LIGHT_SHADOW 关键字在 GLSL 版里是 uniform _CastingPunctualLightShadow。

VARYING vec3 ch20NormalWS;

#ifdef VERTEX
void Ch20ShadowVert()
{
    vec3 positionWS = TransformObjectToWorld(positionOS.xyz);
    vec3 normalWS = TransformObjectToWorldNormal(normalOS);
    vec3 lightDirectionWS = _CastingPunctualLightShadow > 0.5 ? normalize(_LightPosition - positionWS) : _LightDirection;
    vec4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS));
    // WebGL 深度不反转（UNITY_REVERSED_Z = 0）：走 #else 分支
    positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE * positionCS.w);
    gl_Position = positionCS;
    ch20NormalWS = normalWS;
}

void Ch20DepthVert()
{
    gl_Position = TransformObjectToHClip(positionOS.xyz);
    ch20NormalWS = TransformObjectToWorldNormal(normalOS);
}

void main()
{
#ifdef CH20_SHADOW_PASS
    Ch20ShadowVert();
#else
    Ch20DepthVert();
#endif
}
#endif

#ifdef FRAGMENT
void main()
{
#ifdef CH20_DEPTHNORMALS_PASS
    // URP 14 的 _CameraNormalsTexture 存的是归一化的世界空间法线
    fragColor = vec4(NormalizeNormalPerPixel(ch20NormalWS), 0.0);
#elif defined(CH20_DEPTH_PASS)
    fragColor = vec4(gl_FragCoord.z);   // DepthOnly：深度写进 R 通道
#else
    fragColor = vec4(0.0);              // Ch20EmptyFrag
#endif
}
#endif
