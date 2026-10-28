// Cookbook GLSL 光照库：对应 URP 的 RealtimeLights.hlsl / Shadows.hlsl / BRDF.hlsl / GlobalIllumination.hlsl / Lighting.hlsl。
// 自动包含在每个 Shader 里。

// ---------------- 灯光数据（引擎每帧设置） ----------------
#define MAX_VISIBLE_LIGHTS 32
#define MAX_SHADOWED_LIGHTS 8
uniform vec4 _MainLightPosition;     // 方向光：(指向光源的方向, 0)
uniform vec4 _MainLightColor;        // 线性颜色 × 强度
uniform vec4 _AdditionalLightsCount; // x = 数量（Forward+ / Deferred：全部可见附加光）
// Forward 路径：每个物体只受最重要的几盏灯影响（URP Asset 的 Per Object Limit），由引擎逐物体设置
uniform float _PerObjectLights;      // 1 = Forward 逐物体灯光列表
uniform vec4 unity_LightData;        // y = 本物体的灯数
uniform vec4 unity_LightIndices[2];  // 本物体用到的灯在数组里的序号
uniform vec4 _AdditionalLightsPosition[MAX_VISIBLE_LIGHTS];
uniform vec4 _AdditionalLightsColor[MAX_VISIBLE_LIGHTS];
uniform vec4 _AdditionalLightsAttenuation[MAX_VISIBLE_LIGHTS];   // (1/range², 0, 聚光 z, 聚光 w)
uniform vec4 _AdditionalLightsSpotDir[MAX_VISIBLE_LIGHTS];

// ---------------- 阴影 ----------------
uniform highp sampler2DShadow _MainLightShadowmapTexture;
uniform mat4 _MainLightWorldToShadow[5];  // 每级级联一个，见 TransformWorldToShadowCoord
uniform vec4 _MainLightShadowParams;     // (强度, 软阴影档位 0 硬/1 Low/2 Medium/3 High, 淡出 scale, 淡出 bias)
uniform vec4 _MainLightShadowmapSize;    // (1/宽, 1/高, 宽, 高)
uniform highp sampler2DShadow _AdditionalLightsShadowmapTexture;
uniform mat4 _AdditionalLightsWorldToShadow[MAX_SHADOWED_LIGHTS];
uniform vec4 _AdditionalShadowParams[MAX_SHADOWED_LIGHTS];         // (强度, 软阴影档位 0~3, 0, 有阴影?atlas 序号:-1)
uniform vec4 _AdditionalShadowmapSize;
uniform vec4 _ShadowBias;        // 投影 Pass 用：(深度偏移, 法线偏移, 0, 0)
uniform vec3 _LightDirection;    // 投影 Pass 用：方向光的方向
uniform vec3 _LightPosition;     // 投影 Pass 用：点/聚光的位置
uniform float _CastingPunctualLightShadow;

struct Light {
    vec3 direction;
    vec3 color;
    float distanceAttenuation;
    float shadowAttenuation;
};

// ---------------- 级联（URP 的 _CascadeShadowSplitSpheres / ComputeCascadeIndex） ----------------
// 引擎按 URP Asset 的级联数（1~4）、分割比例和阴影距离把主光阴影画进一张图集，每级一格；
// 每级的范围是一个“级联包围球”。_MAIN_LIGHT_SHADOWS_CASCADE 在 GLSL 版里是 uniform：_MainLightShadowsCascade > 0.5（级联数 > 1）
uniform float _MainLightShadowsCascade;
uniform vec4 _CascadeShadowSplitSpheres0, _CascadeShadowSplitSpheres1, _CascadeShadowSplitSpheres2, _CascadeShadowSplitSpheres3;
uniform vec4 _CascadeShadowSplitSphereRadii;   // 半径的平方
float ComputeCascadeIndex(vec3 positionWS) {
    vec3 fromCenter0 = positionWS - _CascadeShadowSplitSpheres0.xyz;
    vec3 fromCenter1 = positionWS - _CascadeShadowSplitSpheres1.xyz;
    vec3 fromCenter2 = positionWS - _CascadeShadowSplitSpheres2.xyz;
    vec3 fromCenter3 = positionWS - _CascadeShadowSplitSpheres3.xyz;
    vec4 distances2 = vec4(dot(fromCenter0, fromCenter0), dot(fromCenter1, fromCenter1), dot(fromCenter2, fromCenter2), dot(fromCenter3, fromCenter3));
    vec4 weights = vec4(lessThan(distances2, _CascadeShadowSplitSphereRadii));
    weights.yzw = saturate(weights.yzw - weights.xyz);
    return 4.0 - dot(weights, vec4(4, 3, 2, 1));   // 0~3；不在任何球里为 4
}

// 每级一个矩阵，第 5 个（序号 4）是“超出所有级联”用的空矩阵：算出的 z = 0，被当成无阴影
// 屏幕空间阴影（URP 的 ScreenSpaceShadows Renderer Feature）：先用深度图把主光阴影算进一张全屏纹理，
// 不透明物体再按屏幕坐标去读。_MAIN_LIGHT_SHADOWS_SCREEN 在 GLSL 版里是 uniform：_MainLightShadowsScreen > 0.5
uniform float _MainLightShadowsScreen;
uniform sampler2D _ScreenSpaceShadowmapTexture;
vec4 TransformWorldToShadowCoord(vec3 positionWS) {
    if (_MainLightShadowsScreen > 0.5) return ComputeScreenPos(TransformWorldToHClip(positionWS));
    int cascadeIndex = _MainLightShadowsCascade > 0.5 ? int(ComputeCascadeIndex(positionWS)) : 0;
    vec4 shadowCoord = _MainLightWorldToShadow[cascadeIndex] * vec4(positionWS, 1.0);
    return vec4(shadowCoord.xyz, 0.0);
}

// 软阴影滤波（URP Shadows.hlsl / ShadowSamplingTent.hlsl）：
//   Low    = 4 次硬件双线性 PCF（±0.5 texel）
//   Medium = 5×5 帐篷滤波，High = 7×7 帐篷滤波：先按帐篷（三角形）覆盖每个 texel 的面积求权重，
//            再把相邻两个 texel 合成一次双线性 PCF，所以 Medium 只要 3×3 = 9 次、High 4×4 = 16 次采样（与 URP 相同）
float ShadowTentCdf(float x, float R) {
    x = clamp(x, -R, R);
    return x <= 0.0 ? (x + R) * (x + R) / (2.0 * R * R) : 1.0 - (R - x) * (R - x) / (2.0 * R * R);
}
float SampleShadowmapTent(highp sampler2DShadow map, vec4 coord, vec4 size, float R, int fetches) {
    vec2 tc = coord.xy * size.zw;          // texel 空间（texel k 覆盖 [k, k+1]）
    vec2 k0 = floor(tc - R);
    vec2 pos[4]; vec2 w[4];
    for (int j = 0; j < fetches; j++) {
        vec2 ka = k0 + float(2 * j);
        vec2 wa = vec2(ShadowTentCdf(ka.x + 1.0 - tc.x, R) - ShadowTentCdf(ka.x - tc.x, R), ShadowTentCdf(ka.y + 1.0 - tc.y, R) - ShadowTentCdf(ka.y - tc.y, R));
        vec2 wb = vec2(ShadowTentCdf(ka.x + 2.0 - tc.x, R) - ShadowTentCdf(ka.x + 1.0 - tc.x, R), ShadowTentCdf(ka.y + 2.0 - tc.y, R) - ShadowTentCdf(ka.y + 1.0 - tc.y, R));
        w[j] = wa + wb;
        pos[j] = ka + 0.5 + wb / max(w[j], vec2(1e-6));   // 两个 texel 中心之间按权重插值的位置
    }
    float s = 0.0;
    for (int y = 0; y < fetches; y++)
        for (int x = 0; x < fetches; x++)
            s += w[x].x * w[y].y * texture(map, vec3(vec2(pos[x].x, pos[y].y) * size.xy, coord.z));
    return s;
}
// softQuality：0 硬阴影，1 Low，2 Medium，3 High（_MainLightShadowParams.y）
float SampleShadowmapFiltered(highp sampler2DShadow map, vec4 coord, vec4 size, float softQuality) {
    if (softQuality < 0.5) return texture(map, coord.xyz);
    if (softQuality < 1.5) {
        vec2 o = 0.5 * size.xy;
        return 0.25 * (texture(map, vec3(coord.xy + vec2(-o.x, -o.y), coord.z)) + texture(map, vec3(coord.xy + vec2(o.x, -o.y), coord.z))
                     + texture(map, vec3(coord.xy + vec2(-o.x, o.y), coord.z)) + texture(map, vec3(coord.xy + vec2(o.x, o.y), coord.z)));
    }
    if (softQuality < 2.5) return SampleShadowmapTent(map, coord, size, 2.5, 3);
    return SampleShadowmapTent(map, coord, size, 3.5, 4);
}
float SampleShadowmapFiltered(highp sampler2DShadow map, vec4 coord, vec4 size, bool soft) {
    return SampleShadowmapFiltered(map, coord, size, soft ? 2.0 : 0.0);
}

float MainLightRealtimeShadow(vec4 shadowCoord) {
    if (_MainLightShadowParams.x <= 0.0) return 1.0;
    if (_MainLightShadowsScreen > 0.5) return texture(_ScreenSpaceShadowmapTexture, shadowCoord.xy / shadowCoord.w).r;   // 已含阴影强度
    // 超出阴影图范围（含远平面之外）视为无阴影，和 URP 的 BEYOND_SHADOW_FAR 一致
    if (shadowCoord.z >= 1.0 || shadowCoord.z <= 0.0 || any(lessThan(shadowCoord.xy, vec2(0.0))) || any(greaterThan(shadowCoord.xy, vec2(1.0)))) return 1.0;
    float a = SampleShadowmapFiltered(_MainLightShadowmapTexture, shadowCoord, _MainLightShadowmapSize, _MainLightShadowParams.y);
    return LerpWhiteTo(a, _MainLightShadowParams.x);
}

float GetMainLightShadowFade(vec3 positionWS) {
    vec3 d = _WorldSpaceCameraPos - positionWS;
    return saturate(dot(d, d) * _MainLightShadowParams.z + _MainLightShadowParams.w);
}

float AdditionalLightRealtimeShadow(int i, vec3 positionWS) {
    if (i >= MAX_SHADOWED_LIGHTS) return 1.0;
    vec4 p = _AdditionalShadowParams[i];
    if (p.w < 0.0 || p.x <= 0.0) return 1.0;
    vec4 c = _AdditionalLightsWorldToShadow[i] * vec4(positionWS, 1.0);
    c.xyz /= c.w;
    if (c.z >= 1.0 || c.z <= 0.0) return 1.0;
    float a = SampleShadowmapFiltered(_AdditionalLightsShadowmapTexture, vec4(c.xyz, 1.0), _AdditionalShadowmapSize, p.y);
    return LerpWhiteTo(a, p.x);
}

// 投影 Pass 的顶点偏移（Shadows.hlsl 的 ApplyShadowBias）
vec3 ApplyShadowBias(vec3 positionWS, vec3 normalWS, vec3 lightDirection) {
    float invNdotL = 1.0 - saturate(dot(lightDirection, normalWS));
    float scale = invNdotL * _ShadowBias.y;
    positionWS = lightDirection * _ShadowBias.xxx + positionWS;
    positionWS = normalWS * scale + positionWS;
    return positionWS;
}
// 默认投影 Pass 的裁剪坐标计算（ShadowCasterPass.hlsl 的 GetShadowPositionHClip）
vec4 GetShadowPositionHClip(vec3 positionOS, vec3 normalOS) {
    vec3 positionWS = TransformObjectToWorld(positionOS);
    vec3 normalWS = TransformObjectToWorldNormal(normalOS);
    vec3 lightDir = _CastingPunctualLightShadow > 0.5 ? normalize(_LightPosition - positionWS) : _LightDirection;
    vec4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDir));
    positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE * positionCS.w);   // 把近平面之前的投影物压到近平面上（pancaking）
    return positionCS;
}

// ---------------- 取灯 ----------------
Light GetMainLight() {
    Light l;
    l.direction = _MainLightPosition.xyz;
    l.color = _MainLightColor.rgb;
    l.distanceAttenuation = 1.0;
    l.shadowAttenuation = 1.0;
    return l;
}
Light GetMainLight(vec4 shadowCoord) {
    Light l = GetMainLight();
    l.shadowAttenuation = MainLightRealtimeShadow(shadowCoord);
    return l;
}
Light GetMainLight(vec4 shadowCoord, vec3 positionWS, vec4 shadowMask) {
    Light l = GetMainLight(shadowCoord);
    l.shadowAttenuation = mix(l.shadowAttenuation, 1.0, GetMainLightShadowFade(positionWS));
    return l;
}

// 距离衰减：物理的 1/d²，再乘一个在 range 处平滑归零的窗口（URP 桌面平台的公式）
float DistanceAttenuation(float distanceSqr, vec2 distanceAttenuation) {
    float lightAtten = 1.0 / max(distanceSqr, 0.0001);
    float factor = distanceSqr * distanceAttenuation.x;
    float smoothFactor = saturate(1.0 - factor * factor);
    smoothFactor = smoothFactor * smoothFactor;
    return lightAtten * smoothFactor;
}
float AngleAttenuation(vec3 spotDirection, vec3 lightDirection, vec2 spotAttenuation) {
    float SdotL = dot(spotDirection, lightDirection);
    float atten = saturate(SdotL * spotAttenuation.x + spotAttenuation.y);
    return atten * atten;
}

int GetAdditionalLightsCount() { return _PerObjectLights > 0.5 ? int(unity_LightData.y) : int(_AdditionalLightsCount.x); }
// 第 i 盏（本物体的）附加光在全局灯光数组里的序号
int GetPerObjectLightIndex(int i) {
    if (_PerObjectLights < 0.5) return i;
    vec4 v = unity_LightIndices[i / 4];
    int k = i - (i / 4) * 4;
    return int(k == 0 ? v.x : k == 1 ? v.y : k == 2 ? v.z : v.w);
}

Light GetAdditionalPerObjectLight(int perObjectIndex, vec3 positionWS) {
    int i = GetPerObjectLightIndex(perObjectIndex);
    vec4 lightPositionWS = _AdditionalLightsPosition[i];
    vec4 att = _AdditionalLightsAttenuation[i];
    vec3 lightVector = lightPositionWS.xyz - positionWS * lightPositionWS.w;
    float distanceSqr = max(dot(lightVector, lightVector), HALF_MIN);
    vec3 lightDirection = lightVector * inversesqrt(distanceSqr);
    float attenuation = DistanceAttenuation(distanceSqr, att.xy) * AngleAttenuation(_AdditionalLightsSpotDir[i].xyz, lightDirection, att.zw);
    Light l;
    l.direction = lightDirection;
    l.distanceAttenuation = attenuation;
    l.shadowAttenuation = 1.0;
    l.color = _AdditionalLightsColor[i].rgb;
    return l;
}
Light GetAdditionalLight(int i, vec3 positionWS) {
    Light l = GetAdditionalPerObjectLight(i, positionWS);
    l.shadowAttenuation = AdditionalLightRealtimeShadow(GetPerObjectLightIndex(i), positionWS);
    return l;
}
Light GetAdditionalLight(int i, vec3 positionWS, vec4 shadowMask) { return GetAdditionalLight(i, positionWS); }

// ---------------- Light Layers ----------------
// URP 的 _LIGHT_LAYERS 关键字在 GLSL 版里是 uniform：_LightLayers > 0.5（URP Asset 打开了 Light Layers）
uniform float _LightLayers;
uniform float _MainLightLayerMask;
uniform float _AdditionalLightsLayerMasks[MAX_VISIBLE_LIGHTS];
uniform vec4 unity_RenderingLayer;   // 每物体：x = Renderer 的 Rendering Layer Mask
uint GetMeshRenderingLayer() { return uint(unity_RenderingLayer.x); }
uint GetMainLightLayerMask() { return uint(_MainLightLayerMask); }
uint GetAdditionalLightLayerMask(int perObjectIndex) { return uint(_AdditionalLightsLayerMasks[GetPerObjectLightIndex(perObjectIndex)]); }
bool IsMatchingLightLayer(uint lightLayers, uint renderingLayers) { return (lightLayers & renderingLayers) != 0u; }

// ---------------- 环境光：球谐 + 反射 ----------------
uniform vec4 unity_SHAr, unity_SHAg, unity_SHAb, unity_SHBr, unity_SHBg, unity_SHBb, unity_SHC;
uniform samplerCube unity_SpecCube0;
uniform vec4 unity_SpecCube0_HDR;   // x = 反射强度
uniform vec4 _GlossyEnvironmentColor;
#define UNITY_SPECCUBE_LOD_STEPS 6.0

vec3 SHEvalLinearL0L1(vec3 N, vec4 shAr, vec4 shAg, vec4 shAb) {
    vec4 vA = vec4(N, 1.0);
    return vec3(dot(shAr, vA), dot(shAg, vA), dot(shAb, vA));
}
vec3 SHEvalLinearL2(vec3 N, vec4 shBr, vec4 shBg, vec4 shBb, vec4 shC) {
    vec4 vB = N.xyzz * N.yzzx;
    vec3 x2 = vec3(dot(shBr, vB), dot(shBg, vB), dot(shBb, vB));
    float vC = N.x * N.x - N.y * N.y;
    return x2 + shC.rgb * vC;
}
vec3 SampleSH(vec3 normalWS) {
    vec3 res = SHEvalLinearL0L1(normalWS, unity_SHAr, unity_SHAg, unity_SHAb);
    res += SHEvalLinearL2(normalWS, unity_SHBr, unity_SHBg, unity_SHBb, unity_SHC);
    return max(vec3(0.0), res);
}
#define SAMPLE_GI(lmUV, shSample, normalWS) SampleSH(normalWS)

vec3 DecodeHDREnvironment(vec4 encoded, vec4 decodeInstructions) { return encoded.rgb * decodeInstructions.x; }
float PerceptualRoughnessToMipmapLevel(float pr) { return pr * (1.7 - 0.7 * pr) * UNITY_SPECCUBE_LOD_STEPS; }
vec3 GlossyEnvironmentReflection(vec3 reflectVector, float perceptualRoughness, float occlusion) {
#ifdef _ENVIRONMENTREFLECTIONS_OFF
    return _GlossyEnvironmentColor.rgb * occlusion;
#endif
    float mip = PerceptualRoughnessToMipmapLevel(perceptualRoughness);
    vec4 encoded = textureLod(unity_SpecCube0, reflectVector, mip);
    return DecodeHDREnvironment(encoded, unity_SpecCube0_HDR) * occlusion;
}
vec3 GlossyEnvironmentReflection(vec3 reflectVector, vec3 positionWS, float perceptualRoughness, float occlusion) {
    return GlossyEnvironmentReflection(reflectVector, perceptualRoughness, occlusion);
}

// URP 14 的 5 参数版本（带屏幕 UV，用于反射探针混合等；网页版忽略 UV）
vec3 GlossyEnvironmentReflection(vec3 reflectVector, vec3 positionWS, float perceptualRoughness, float occlusion, vec2 normalizedScreenSpaceUV) {
    return GlossyEnvironmentReflection(reflectVector, perceptualRoughness, occlusion);
}

// ---------------- BRDF（BRDF.hlsl） ----------------
#define kDielectricSpec vec4(0.04, 0.04, 0.04, 1.0 - 0.04)
#define HALF_MIN_SQRT 0.0078125

struct BRDFData {
    vec3 albedo;
    vec3 diffuse;
    vec3 specular;
    float reflectivity;
    float perceptualRoughness;
    float roughness;
    float roughness2;
    float grazingTerm;
    float normalizationTerm;   // roughness * 4 + 2
    float roughness2MinusOne;
};

float OneMinusReflectivityMetallic(float metallic) {
    float oneMinusDielectricSpec = kDielectricSpec.a;
    return oneMinusDielectricSpec - metallic * oneMinusDielectricSpec;
}
float PerceptualSmoothnessToPerceptualRoughness(float s) { return 1.0 - s; }
float PerceptualRoughnessToRoughness(float pr) { return pr * pr; }

void InitializeBRDFDataDirect(vec3 albedo, vec3 diffuse, vec3 specular, float reflectivity, float oneMinusReflectivity, float smoothness, inout float alpha, out BRDFData o) {
    o.albedo = albedo;
    o.diffuse = diffuse;
    o.specular = specular;
    o.reflectivity = reflectivity;
    o.perceptualRoughness = PerceptualSmoothnessToPerceptualRoughness(smoothness);
    o.roughness = max(PerceptualRoughnessToRoughness(o.perceptualRoughness), HALF_MIN_SQRT);
    o.roughness2 = max(o.roughness * o.roughness, HALF_MIN);
    o.grazingTerm = saturate(smoothness + reflectivity);
    o.normalizationTerm = o.roughness * 4.0 + 2.0;
    o.roughness2MinusOne = o.roughness2 - 1.0;
#ifdef _ALPHAPREMULTIPLY_ON
    o.diffuse *= alpha;
#endif
}

void InitializeBRDFData(vec3 albedo, float metallic, vec3 specular, float smoothness, inout float alpha, out BRDFData o) {
#ifdef _SPECULAR_SETUP
    float reflectivity = max(max(specular.r, specular.g), specular.b);
    float oneMinusReflectivity = 1.0 - reflectivity;
    vec3 brdfDiffuse = albedo * oneMinusReflectivity;   // 与 URP BRDF.hlsl 一致：按最大分量的反射率整体压暗，不是逐通道 1-specular
    vec3 brdfSpecular = specular;
#else
    float oneMinusReflectivity = OneMinusReflectivityMetallic(metallic);
    float reflectivity = 1.0 - oneMinusReflectivity;
    vec3 brdfDiffuse = albedo * oneMinusReflectivity;
    vec3 brdfSpecular = mix(kDielectricSpec.rgb, albedo, metallic);
#endif
    InitializeBRDFDataDirect(albedo, brdfDiffuse, brdfSpecular, reflectivity, oneMinusReflectivity, smoothness, alpha, o);
#ifdef _ALPHAPREMULTIPLY_ON
    alpha = alpha * oneMinusReflectivity + reflectivity;
#endif
}

// 直接光高光：D·V·F 的 URP 近似（GGX + 简化的可见性/菲涅尔项）
float DirectBRDFSpecular(BRDFData b, vec3 normalWS, vec3 lightDirectionWS, vec3 viewDirectionWS) {
    vec3 H = SafeNormalize(lightDirectionWS + viewDirectionWS);
    float NoH = saturate(dot(normalWS, H));
    float LoH = saturate(dot(lightDirectionWS, H));
    float d = NoH * NoH * b.roughness2MinusOne + 1.00001;
    float LoH2 = LoH * LoH;
    return b.roughness2 / ((d * d) * max(0.1, LoH2) * b.normalizationTerm);
}

vec3 LightingPhysicallyBased(BRDFData b, vec3 lightColor, vec3 lightDirectionWS, float lightAttenuation, vec3 normalWS, vec3 viewDirectionWS, bool specularHighlightsOff) {
    float NdotL = saturate(dot(normalWS, lightDirectionWS));
    vec3 radiance = lightColor * (lightAttenuation * NdotL);
    vec3 brdf = b.diffuse;
    if (!specularHighlightsOff) brdf += b.specular * DirectBRDFSpecular(b, normalWS, lightDirectionWS, viewDirectionWS);
    return brdf * radiance;
}
vec3 LightingPhysicallyBased(BRDFData b, Light light, vec3 normalWS, vec3 viewDirectionWS, bool specularHighlightsOff) {
    return LightingPhysicallyBased(b, light.color, light.direction, light.distanceAttenuation * light.shadowAttenuation, normalWS, viewDirectionWS, specularHighlightsOff);
}
vec3 LightingPhysicallyBased(BRDFData b, Light light, vec3 normalWS, vec3 viewDirectionWS) {
    return LightingPhysicallyBased(b, light, normalWS, viewDirectionWS, false);
}

vec3 EnvironmentBRDFSpecular(BRDFData b, float fresnelTerm) {
    float surfaceReduction = 1.0 / (b.roughness2 + 1.0);
    return surfaceReduction * mix(b.specular, vec3(b.grazingTerm), fresnelTerm);
}
vec3 EnvironmentBRDF(BRDFData b, vec3 indirectDiffuse, vec3 indirectSpecular, float fresnelTerm) {
    vec3 c = indirectDiffuse * b.diffuse;
    c += indirectSpecular * EnvironmentBRDFSpecular(b, fresnelTerm);
    return c;
}
vec3 GlobalIllumination(BRDFData b, vec3 bakedGI, float occlusion, vec3 positionWS, vec3 normalWS, vec3 viewDirectionWS) {
    vec3 reflectVector = reflect(-viewDirectionWS, normalWS);
    float NoV = saturate(dot(normalWS, viewDirectionWS));
    float fresnelTerm = Pow4(1.0 - NoV);
    vec3 indirectDiffuse = bakedGI;
    vec3 indirectSpecular = GlossyEnvironmentReflection(reflectVector, positionWS, b.perceptualRoughness, 1.0);
    return EnvironmentBRDF(b, indirectDiffuse, indirectSpecular, fresnelTerm) * occlusion;
}

// ---------------- SurfaceData / InputData 与 UniversalFragmentPBR（Lighting.hlsl） ----------------
struct SurfaceData {
    vec3 albedo;
    vec3 specular;
    float metallic;
    float smoothness;
    vec3 normalTS;
    vec3 emission;
    float occlusion;
    float alpha;
    float clearCoatMask;
    float clearCoatSmoothness;
};
struct InputData {
    vec3 positionWS;
    vec4 positionCS;
    vec3 normalWS;
    vec3 viewDirectionWS;
    vec4 shadowCoord;
    float fogCoord;
    vec3 vertexLighting;
    vec3 bakedGI;
    vec2 normalizedScreenSpaceUV;
    vec4 shadowMask;
    mat3 tangentToWorld;
};
SurfaceData InitSurfaceData() {
    SurfaceData s;
    s.albedo = vec3(1.0); s.specular = vec3(0.0); s.metallic = 0.0; s.smoothness = 0.5; s.normalTS = vec3(0, 0, 1);
    s.emission = vec3(0.0); s.occlusion = 1.0; s.alpha = 1.0; s.clearCoatMask = 0.0; s.clearCoatSmoothness = 0.0;
    return s;
}
InputData InitInputData() {
    InputData d;
    d.positionWS = vec3(0.0); d.positionCS = vec4(0.0); d.normalWS = vec3(0, 1, 0); d.viewDirectionWS = vec3(0, 0, 1);
    d.shadowCoord = vec4(0.0); d.fogCoord = 0.0; d.vertexLighting = vec3(0.0); d.bakedGI = vec3(0.0);
    d.normalizedScreenSpaceUV = vec2(0.0); d.shadowMask = vec4(1.0); d.tangentToWorld = mat3(1.0);
    return d;
}

// 屏幕空间 AO（SSAO Renderer Feature 打开时由引擎提供）
uniform sampler2D _ScreenSpaceOcclusionTexture;
uniform vec4 _AmbientOcclusionParam;   // (0, 0, 0, 直接光 AO 强度)；x = 1 表示启用
struct AmbientOcclusionFactor { float indirectAmbientOcclusion; float directAmbientOcclusion; };
AmbientOcclusionFactor GetScreenSpaceAmbientOcclusion(vec2 uv) {
    AmbientOcclusionFactor f;
    f.indirectAmbientOcclusion = 1.0; f.directAmbientOcclusion = 1.0;
    if (_AmbientOcclusionParam.x > 0.5) {
        float ssao = texture(_ScreenSpaceOcclusionTexture, uv).r;
        f.indirectAmbientOcclusion = ssao;
        f.directAmbientOcclusion = mix(1.0, ssao, _AmbientOcclusionParam.w);
    }
    return f;
}
AmbientOcclusionFactor CreateAmbientOcclusionFactor(InputData d, SurfaceData s) {
    AmbientOcclusionFactor f = GetScreenSpaceAmbientOcclusion(d.normalizedScreenSpaceUV);
    f.indirectAmbientOcclusion = min(f.indirectAmbientOcclusion, s.occlusion);
    return f;
}

vec4 UniversalFragmentPBR(InputData inputData, SurfaceData surfaceData) {
    bool specularHighlightsOff = false;
#ifdef _SPECULARHIGHLIGHTS_OFF
    specularHighlightsOff = true;
#endif
    BRDFData brdfData;
    InitializeBRDFData(surfaceData.albedo, surfaceData.metallic, surfaceData.specular, surfaceData.smoothness, surfaceData.alpha, brdfData);
    AmbientOcclusionFactor ao = CreateAmbientOcclusionFactor(inputData, surfaceData);
    Light mainLight = GetMainLight(inputData.shadowCoord, inputData.positionWS, inputData.shadowMask);
    mainLight.color *= ao.directAmbientOcclusion;

    vec3 giColor = GlobalIllumination(brdfData, inputData.bakedGI, ao.indirectAmbientOcclusion, inputData.positionWS, inputData.normalWS, inputData.viewDirectionWS);
    vec3 mainLightColor = LightingPhysicallyBased(brdfData, mainLight, inputData.normalWS, inputData.viewDirectionWS, specularHighlightsOff);
    vec3 additional = vec3(0.0);
    for (int i = 0; i < GetAdditionalLightsCount(); i++) {
        Light light = GetAdditionalLight(i, inputData.positionWS, inputData.shadowMask);
        light.color *= ao.directAmbientOcclusion;
        additional += LightingPhysicallyBased(brdfData, light, inputData.normalWS, inputData.viewDirectionWS, specularHighlightsOff);
    }
    vec3 color = giColor + mainLightColor + additional + inputData.vertexLighting * brdfData.diffuse + surfaceData.emission;
    return vec4(color, surfaceData.alpha);
}
vec4 UniversalFragmentPBR(InputData d, vec3 albedo, float metallic, vec3 specular, float smoothness, float occlusion, vec3 emission, float alpha) {
    SurfaceData s = InitSurfaceData();
    s.albedo = albedo; s.metallic = metallic; s.specular = specular; s.smoothness = smoothness;
    s.occlusion = occlusion; s.emission = emission; s.alpha = alpha;
    return UniversalFragmentPBR(d, s);
}

// ---------------- Blinn-Phong（SimpleLit） ----------------
vec3 LightingLambert(vec3 lightColor, vec3 lightDir, vec3 normal) {
    return lightColor * saturate(dot(normal, lightDir));
}
vec3 LightingSpecular(vec3 lightColor, vec3 lightDir, vec3 normal, vec3 viewDir, vec4 specular, float smoothness) {
    vec3 halfVec = SafeNormalize(lightDir + viewDir);
    float NdotH = saturate(dot(normal, halfVec));
    float modifier = pow(NdotH, smoothness);
    return lightColor * (specular.rgb * modifier);
}
vec3 CalculateBlinnPhong(Light light, InputData d, SurfaceData s) {
    vec3 attenuatedLightColor = light.color * (light.distanceAttenuation * light.shadowAttenuation);
    vec3 lightDiffuseColor = LightingLambert(attenuatedLightColor, light.direction, d.normalWS);
    vec3 lightSpecularColor = vec3(0.0);
#if defined(_SPECGLOSSMAP) || defined(_SPECULAR_COLOR)
    float smoothness = exp2(10.0 * s.smoothness + 1.0);
    lightSpecularColor += LightingSpecular(attenuatedLightColor, light.direction, d.normalWS, d.viewDirectionWS, vec4(s.specular, 1.0), smoothness);
#endif
    return lightDiffuseColor * s.albedo + lightSpecularColor;
}
vec4 UniversalFragmentBlinnPhong(InputData d, SurfaceData s) {
    AmbientOcclusionFactor ao = CreateAmbientOcclusionFactor(d, s);
    Light mainLight = GetMainLight(d.shadowCoord, d.positionWS, d.shadowMask);
    vec3 color = d.bakedGI * s.albedo * ao.indirectAmbientOcclusion;
    color += CalculateBlinnPhong(mainLight, d, s);
    for (int i = 0; i < GetAdditionalLightsCount(); i++) {
        Light light = GetAdditionalLight(i, d.positionWS, d.shadowMask);
        color += CalculateBlinnPhong(light, d, s);
    }
    color += s.emission;
    return vec4(color, s.alpha);
}
