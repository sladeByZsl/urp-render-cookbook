// 案例 6.4 手写 ShadowCaster Pass：把物体画进光源的阴影图（只写深度）。（GLSL 版，对应 Ch06/ShadowCasterPass.hlsl）
// 用法：在 Pass 里先声明好材质 uniform（需要 Alpha 裁剪时要有 _BaseMap/_BaseMap_ST/_BaseColor/_Cutoff），再 include 本文件。
// ApplyShadowBias 在自动包含的 Lighting.glsl 里（对应 URP 的 Shadows.hlsl）。

//#region lightparams
// 由 URP 的 MainLightShadowCasterPass / AdditionalLightsShadowCasterPass 在画每个阴影切片前设置
// （见 Runtime/ShadowUtils.cs 的 SetupShadowCasterConstantBuffer）。
// GLSL 版里 _LightDirection / _LightPosition 已在 Lighting.glsl 里声明：
//   uniform vec3 _LightDirection;   // 方向光：指向光源的方向
//   uniform vec3 _LightPosition;    // 点光 / 聚光：光源的世界坐标
//#endregion

#if defined(_ALPHATEST_ON)
VARYING vec2 uv;
#endif

//#region shadowpos
vec4 GetShadowCasterPositionCS(vec3 positionWS, vec3 normalWS)
{
    // 1) 求“指向光源”的方向：方向光处处相同；点光/聚光每个顶点不同
    //    （HLSL 里的 _CASTING_PUNCTUAL_LIGHT_SHADOW 关键字，在 GLSL 版里是一个 uniform）
    vec3 lightDirectionWS = _CastingPunctualLightShadow > 0.5 ? normalize(_LightPosition - positionWS) : _LightDirection;

    // 2) 在世界空间里做深度偏移 + 法线偏移，再变换到光源的裁剪空间
    //    （此刻 UNITY_MATRIX_VP 已被 URP 设成了“光源相机”的 VP 矩阵）
    vec4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS));

    // 3) 把跑到近平面之外的顶点“压扁”到近平面上（Shadow Pancaking），
    //    否则光源近平面之前的投射体会被裁掉，阴影凭空缺一块
#if UNITY_REVERSED_Z
    positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
#else
    positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
#endif
    return positionCS;
}
//#endregion

#ifdef VERTEX
void main()
{
    vec3 positionWS = TransformObjectToWorld(positionOS.xyz);
    vec3 normalWS = TransformObjectToWorldNormal(normalOS);
    gl_Position = GetShadowCasterPositionCS(positionWS, normalWS);
#if defined(_ALPHATEST_ON)
    uv = TransformTex(texcoord0.xy, _BaseMap_ST);
#endif
}
#endif

#ifdef FRAGMENT
void main()
{
#if defined(_ALPHATEST_ON)
    // 镂空材质的影子也要镂空：和颜色 Pass 用同样的 clip
    float alpha = texture(_BaseMap, uv).a * _BaseColor.a;
    if (alpha - _Cutoff < 0.0) discard;
#endif
    fragColor = vec4(0.0);
}
#endif
