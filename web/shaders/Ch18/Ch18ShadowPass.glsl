// 本章不透明 Shader 共用的 ShadowCaster / DepthOnly 顶点与片元函数（无顶点动画、无裁剪）。（GLSL 版，对应 Ch18ShadowPass.hlsl）
// 用法：在 Pass 的 GLSLPROGRAM 里先 #define SHADOW_PASS 或 DEPTH_PASS，再 #include 本文件。
// HLSL 版强调所有 Pass 的 CBUFFER 一致（SRP Batcher）；WebGL 没有这个概念，这里只保留顶点/片元逻辑。
// _LightDirection / _LightPosition 由引擎在画阴影前设置（Lighting.glsl 里已声明）。

#ifdef SHADOW_PASS
#ifdef VERTEX
void main()
{
    vec3 positionWS = TransformObjectToWorld(positionOS.xyz);
    vec3 normalWS = TransformObjectToWorldNormal(normalOS);
    // _CASTING_PUNCTUAL_LIGHT_SHADOW 在 GLSL 版里是个 uniform
    vec3 lightDirWS = _CastingPunctualLightShadow > 0.5 ? normalize(_LightPosition - positionWS) : _LightDirection;
    vec4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirWS));
    // WebGL 深度不反转（UNITY_REVERSED_Z = 0），走 max 分支
    positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE * positionCS.w);
    gl_Position = positionCS;
}
#endif
#ifdef FRAGMENT
void main() { fragColor = vec4(0.0); }
#endif
#endif

#ifdef DEPTH_PASS
#ifdef VERTEX
void main() { gl_Position = TransformObjectToHClip(positionOS.xyz); }
#endif
#ifdef FRAGMENT
void main() { fragColor = vec4(gl_FragCoord.z); }
#endif
#endif
