// URP Lit 的材质参数与采样函数（LitInput.hlsl / SurfaceInput.hlsl）
uniform sampler2D _BaseMap;     uniform vec4 _BaseMap_ST;
uniform vec4 _BaseColor;
uniform float _Cutoff;
uniform float _Smoothness;
uniform float _Metallic;
uniform vec4 _SpecColor;
uniform sampler2D _MetallicGlossMap;
uniform sampler2D _SpecGlossMap;
uniform sampler2D _BumpMap;     uniform float _BumpScale;
uniform sampler2D _OcclusionMap; uniform float _OcclusionStrength;
uniform sampler2D _EmissionMap; uniform vec4 _EmissionColor;
uniform sampler2D _ParallaxMap; uniform float _Parallax;
uniform float _Surface;

vec4 SampleAlbedoAlpha(vec2 uv) { return texture(_BaseMap, uv); }

float Alpha(float albedoAlpha, vec4 color, float cutoff)
{
    float alpha = albedoAlpha * color.a;
#ifdef _ALPHATEST_ON
    if (alpha - cutoff < 0.0) discard;
#endif
    return alpha;
}

vec4 SampleMetallicSpecGloss(vec2 uv, float albedoAlpha)
{
    vec4 specGloss;
#ifdef _METALLICSPECGLOSSMAP
  #ifdef _SPECULAR_SETUP
    specGloss = texture(_SpecGlossMap, uv);
  #else
    specGloss = texture(_MetallicGlossMap, uv);
  #endif
  #ifdef _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
    specGloss.a = albedoAlpha * _Smoothness;
  #else
    specGloss.a *= _Smoothness;
  #endif
#else
  #ifdef _SPECULAR_SETUP
    specGloss.rgb = _SpecColor.rgb;
  #else
    specGloss.rgb = vec3(_Metallic);
  #endif
  #ifdef _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
    specGloss.a = albedoAlpha * _Smoothness;
  #else
    specGloss.a = _Smoothness;
  #endif
#endif
    return specGloss;
}

vec3 SampleNormal(vec2 uv, float scale)
{
#ifdef _NORMALMAP
    return UnpackNormalScale(texture(_BumpMap, uv), scale);
#else
    return vec3(0.0, 0.0, 1.0);
#endif
}

float SampleOcclusion(vec2 uv)
{
#ifdef _OCCLUSIONMAP
    return LerpWhiteTo(texture(_OcclusionMap, uv).g, _OcclusionStrength);
#else
    return 1.0;
#endif
}

vec3 SampleEmission(vec2 uv)
{
#ifdef _EMISSION
    return texture(_EmissionMap, uv).rgb * _EmissionColor.rgb;
#else
    return vec3(0.0);
#endif
}

SurfaceData InitializeStandardLitSurfaceData(vec2 uv)
{
    SurfaceData s = InitSurfaceData();
    vec4 albedoAlpha = SampleAlbedoAlpha(uv);
    s.alpha = Alpha(albedoAlpha.a, _BaseColor, _Cutoff);
    vec4 specGloss = SampleMetallicSpecGloss(uv, albedoAlpha.a);
    s.albedo = albedoAlpha.rgb * _BaseColor.rgb;
#ifdef _SPECULAR_SETUP
    s.metallic = 1.0;
    s.specular = specGloss.rgb;
#else
    s.metallic = specGloss.r;
    s.specular = vec3(0.0);
#endif
    s.smoothness = specGloss.a;
    s.normalTS = SampleNormal(uv, _BumpScale);
    s.occlusion = SampleOcclusion(uv);
    s.emission = SampleEmission(uv);
    return s;
}
