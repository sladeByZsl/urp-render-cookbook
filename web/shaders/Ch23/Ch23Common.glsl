// 第 23 章共用：一个最小的 ShadowCaster / DepthOnly 实现（GLSL 版，对应 Ch23Common.hlsl）。
// 写法与 URP 14 的 Shaders/ShadowCasterPass.hlsl 一致，只是去掉了 Alpha 裁剪和 LOD 交叉淡化，
// 让本章的各个 Shader 不必依赖 LitInput 的材质变量。
// _LightDirection / _LightPosition / _ShadowBias 由引擎每盏灯设置一次（Lighting.glsl 里已声明）。

#ifdef VERTEX
//#region caster
vec4 Ch23ShadowCasterVert()
{
    vec3 positionWS = TransformObjectToWorld(positionOS.xyz);
    vec3 normalWS   = TransformObjectToWorldNormal(normalOS);

    // _CASTING_PUNCTUAL_LIGHT_SHADOW 关键字在 GLSL 版里是个 uniform
    vec3 lightDirectionWS = _CastingPunctualLightShadow > 0.5 ? normalize(_LightPosition - positionWS) : _LightDirection;
    // Depth Bias 沿光线方向推远、Normal Bias 沿法线向内收缩，都在投射端完成
    vec4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS));

    // 把超出近裁剪面的投射体压到近平面上（Pancaking），避免它们被裁掉后漏光
    // WebGL 深度不反转（UNITY_REVERSED_Z = 0），走 max 分支
    positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE * positionCS.w);
    return positionCS;
}
//#endregion

vec4 Ch23DepthOnlyVert()
{
    return TransformObjectToHClip(positionOS.xyz);
}
#endif

#ifdef FRAGMENT
vec4 Ch23NullFrag() { return vec4(0.0); }
#endif

// 便捷写法：在 Pass 里 #define CH23_SHADOW_PASS / CH23_DEPTH_PASS 后 include 本文件，直接得到 main()
#ifdef CH23_SHADOW_PASS
#ifdef VERTEX
void main() { gl_Position = Ch23ShadowCasterVert(); }
#endif
#ifdef FRAGMENT
void main() { fragColor = Ch23NullFrag(); }
#endif
#endif

#ifdef CH23_DEPTH_PASS
#ifdef VERTEX
void main() { gl_Position = Ch23DepthOnlyVert(); }
#endif
#ifdef FRAGMENT
void main() { fragColor = vec4(gl_FragCoord.z); }
#endif
#endif
