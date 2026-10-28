// 第 5 章所有 Shader 共用的 ShadowCaster / DepthOnly 顶点与片元代码（GLSL 版）。
// 原理（ApplyShadowBias、点光源投影等）在第 6 章细讲。
// 用法：在 Pass 的 GLSLPROGRAM 里先 #define SHADOW_PASS 或 DEPTH_PASS，再 #include 本文件。

#ifdef SHADOW_PASS
#ifdef VERTEX
void main()
{
    vec3 positionWS = TransformObjectToWorld(positionOS.xyz);
    vec3 normalWS = TransformObjectToWorldNormal(normalOS);
    // 点光源/聚光灯：方向从顶点指向灯；方向光：所有顶点同一方向（_CASTING_PUNCTUAL_LIGHT_SHADOW 在 GLSL 版里是个 uniform）
    vec3 lightDirectionWS = _CastingPunctualLightShadow > 0.5 ? normalize(_LightPosition - positionWS) : _LightDirection;
    vec4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS));
    positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE * positionCS.w);
    gl_Position = positionCS;
}
#endif
#ifdef FRAGMENT
void main() { fragColor = vec4(0.0); }   // ColorMask 0，只写深度
#endif
#endif

#ifdef DEPTH_PASS
#ifdef VERTEX
void main() { gl_Position = TransformObjectToHClip(positionOS.xyz); }
#endif
#ifdef FRAGMENT
void main() { fragColor = vec4(gl_FragCoord.z); }   // 与 URP DepthOnlyPass 一致：深度写进 R 通道
#endif
#endif
