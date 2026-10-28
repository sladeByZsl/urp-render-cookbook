// 第 7 章公用代码：简化光照 + ShadowCaster/DepthOnly 两个辅助 Pass。（GLSL 版，对应 Ch07/Ch07Common.hlsl）
// 本章的重点是“法线从哪来”，光照模型沿用第 5、6 章的 Lambert + 归一化 Blinn-Phong + 球谐环境光，
// 这样不同案例之间的差别只来自法线和 UV，便于对比。
// 用法：颜色 Pass 直接 include，调用 Ch07Shade；
//       投影 / 深度 Pass 先 #define CH07_SHADOW_PASS 或 CH07_DEPTH_PASS 再 include（对应 HLSL 的 #pragma vertex Ch07ShadowVert 等）。

//#region shade
// positionWS/normalWS：世界空间位置与（已经过法线贴图扰动的）法线
// gloss：0~1 映射到高光指数 2~2048；specStrength：高光强度
// extraShadow：额外的阴影系数（视差自阴影会用到），没有就传 1
vec3 Ch07Shade(vec3 positionWS, vec3 normalWS, vec3 albedo, float gloss, float specStrength, float extraShadow)
{
    vec4 shadowCoord = TransformWorldToShadowCoord(positionWS);
    Light mainLight = GetMainLight(shadowCoord);

    vec3 V = GetWorldSpaceNormalizeViewDir(positionWS);
    vec3 L = mainLight.direction;
    vec3 H = SafeNormalize(L + V);
    float NdotL = saturate(dot(normalWS, L));
    float NdotH = saturate(dot(normalWS, H));

    // URP 的灯光强度已经“乘过 π”，所以 Lambert 不再除 π，
    // 归一化 Blinn-Phong 的 (n+8)/(8π) 同理写成 (n+8)/8
    float n = exp2(gloss * 10.0 + 1.0);
    float spec = specStrength * (n + 8.0) / 8.0 * pow(NdotH, n);

    float atten = mainLight.shadowAttenuation * mainLight.distanceAttenuation * extraShadow;
    vec3 direct = (albedo + spec) * NdotL * atten * mainLight.color;
    vec3 ambient = SampleSH(normalWS) * albedo;     // 环境光：球谐（第 8 章细讲）
    return direct + ambient;
}
//#endregion

//#region passes
// ShadowCaster 与 DepthOnly：只依赖顶点位置和法线，与表面着色无关。
// _LightDirection/_LightPosition 由 URP 在渲染阴影时设置（见 ShadowUtils.SetupShadowCasterConstantBuffer），
// GLSL 版里它们已在 Lighting.glsl 中声明；_CASTING_PUNCTUAL_LIGHT_SHADOW 是 uniform _CastingPunctualLightShadow
#ifdef VERTEX
vec4 Ch07ShadowVert()
{
    vec3 positionWS = TransformObjectToWorld(positionOS.xyz);
    vec3 normalWS = TransformObjectToWorldNormal(normalOS);
    vec3 lightDirectionWS = _CastingPunctualLightShadow > 0.5 ? normalize(_LightPosition - positionWS) : _LightDirection;
    vec4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS));
#if UNITY_REVERSED_Z
    positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
#else
    positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
#endif
    return positionCS;
}

vec4 Ch07DepthVert()
{
    return TransformObjectToHClip(positionOS.xyz);
}

#if defined(CH07_SHADOW_PASS)
void main() { gl_Position = Ch07ShadowVert(); }
#elif defined(CH07_DEPTH_PASS)
void main() { gl_Position = Ch07DepthVert(); }
#endif
#endif

#ifdef FRAGMENT
vec4 Ch07NullFrag()
{
    return vec4(0.0);
}
#if defined(CH07_SHADOW_PASS) || defined(CH07_DEPTH_PASS)
void main() { fragColor = Ch07NullFrag(); }
#endif
#endif
//#endregion
