// 案例 6.9 ClassicLit 的前向 Pass：归一化 Blinn-Phong + 球谐环境光 + 主光阴影 + 附加光（Forward / Forward+）
// + 附加光阴影 + Light Layers + SSAO + 雾（GLSL 版，对应 Ch06/ClassicLitForwardPass.hlsl）
// 网页版没有光照 Cookie 和逐顶点阴影坐标插值（REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR），这两段省略。

VARYING vec2 uv;
VARYING vec3 positionWS;
VARYING vec3 normalWS;
VARYING vec4 fogFactorAndVertexLight;   // x：雾；yzw：逐顶点附加光

//#region vert
#ifdef VERTEX
// URP 的 VertexLighting()：只有 _ADDITIONAL_LIGHTS_VERTEX（逐顶点附加光）时才非零
vec3 VertexLighting(vec3 positionWS, vec3 normalWS)
{
    vec3 vertexLightColor = vec3(0.0);
#if defined(_ADDITIONAL_LIGHTS_VERTEX)
    for (int i = 0; i < GetAdditionalLightsCount(); i++)
    {
        Light light = GetAdditionalPerObjectLight(i, positionWS);
        vertexLightColor += LightingLambert(light.color * light.distanceAttenuation, light.direction, normalWS);
    }
#endif
    return vertexLightColor;
}

void main()
{
    VertexPositionInputs vertexInput = GetVertexPositionInputs(positionOS.xyz);
    vec3 nWS = TransformObjectToWorldNormal(normalOS);

    gl_Position = vertexInput.positionCS;
    positionWS = vertexInput.positionWS;
    normalWS = nWS;
    uv = TransformTex(texcoord0.xy, _BaseMap_ST);

    float fogFactor = ComputeFogFactor(vertexInput.positionCS.z);
    vec3 vertexLight = VertexLighting(vertexInput.positionWS, nWS);   // 只有 _ADDITIONAL_LIGHTS_VERTEX 时非零
    fogFactorAndVertexLight = vec4(fogFactor, vertexLight);
}
#endif
//#endregion

#ifdef FRAGMENT
//#region inputdata
InputData BuildInputData(vec3 normalWS)
{
    InputData inputData = InitInputData();
    inputData.positionWS = positionWS;
    inputData.positionCS = gl_FragCoord;
    inputData.normalWS = normalWS;
    inputData.viewDirectionWS = GetWorldSpaceNormalizeViewDir(positionWS);
#if defined(_RECEIVE_SHADOWS_OFF)
    inputData.shadowCoord = vec4(0, 0, 0, 0);                               // 不接收阴影：URP 不定义 MAIN_LIGHT_CALCULATE_SHADOWS
#else
    inputData.shadowCoord = TransformWorldToShadowCoord(positionWS);        // 级联：逐像素选级联
#endif
    // URP 14 强制逐像素算雾（_FOG_FRAGMENT），这里按像素位置重新求雾因子，顶点雾因子只作后备
    inputData.fogCoord = ComputeFogFactor(TransformWorldToHClip(positionWS).z);
    inputData.vertexLighting = fogFactorAndVertexLight.yzw;
    inputData.bakedGI = SampleSH(normalWS);                     // 本章只用球谐环境光，光照贴图见第 8 章
    inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(gl_FragCoord);
    inputData.shadowMask = vec4(1, 1, 1, 1);                    // 没有烘焙阴影时为 1
    return inputData;
}
//#endregion

//#region blinnphong
// 一盏灯的贡献：归一化 Blinn-Phong（URP 约定，漫反射不除 π，高光系数为 (n+8)/8）
vec3 ClassicBlinnPhong(Light light, vec3 normalWS, vec3 viewDirWS, vec3 albedo, vec3 specColor, float shininess)
{
    float NdotL = saturate(dot(normalWS, light.direction));
    vec3 radiance = light.color * (light.distanceAttenuation * light.shadowAttenuation * NdotL);

    vec3 H = SafeNormalize(light.direction + viewDirWS);
    float NdotH = saturate(dot(normalWS, H));
    float spec = (shininess + 8.0) * 0.125 * pow(NdotH, shininess);

    return (albedo + specColor * spec) * radiance;
}
//#endregion

//#region frag
void main()
{
    vec4 baseSample = texture(_BaseMap, uv) * _BaseColor;
#if defined(_ALPHATEST_ON)
    if (baseSample.a - _Cutoff < 0.0) discard;
#endif
    vec3 albedo = baseSample.rgb;
    vec3 specColor = _SpecColor.rgb;
    float shininess = exp2(10.0 * _Smoothness + 1.0);        // 与 URP SimpleLit 相同的映射

    vec3 N = NormalizeNormalPerPixel(normalWS);
    InputData inputData = BuildInputData(N);

    vec4 shadowMask = inputData.shadowMask;                   // URP：CalculateShadowMask(inputData)
    // URP：CreateAmbientOcclusionFactor(uv, 1.0)。没开 SSAO 时两项都是 1
    AmbientOcclusionFactor aoFactor = GetScreenSpaceAmbientOcclusion(inputData.normalizedScreenSpaceUV);
    uint meshRenderingLayers = GetMeshRenderingLayer();

    // ---- 环境光（SSAO 只压暗间接光，直接光按 Direct Lighting Strength 衰减）----
    vec3 color = inputData.bakedGI * albedo * aoFactor.indirectAmbientOcclusion;

    // ---- 主光源：带阴影、阴影淡出（URP 的 GetMainLight(inputData, shadowMask, aoFactor)）----
    Light mainLight = GetMainLight(inputData.shadowCoord, inputData.positionWS, shadowMask);
    mainLight.color *= aoFactor.directAmbientOcclusion;
    // HLSL 版的 #if defined(_LIGHT_LAYERS)：GLSL 版里是 uniform _LightLayers（URP Asset 打开 Light Layers 时为 1）
    if (_LightLayers < 0.5 || IsMatchingLightLayer(GetMainLightLayerMask(), meshRenderingLayers))
        color += ClassicBlinnPhong(mainLight, N, inputData.viewDirectionWS, albedo, specColor, shininess);

    // ---- 附加光源 ----
#if defined(_ADDITIONAL_LIGHTS)
    // HLSL 版：Forward+ 先单独循环附加方向光，再用 LIGHT_LOOP_BEGIN 遍历分簇结构；
    // 网页版统一成普通 for 循环（Forward 下是本物体的灯，Forward+ 下是全部可见附加光，方向光在最前面）
    int pixelLightCount = GetAdditionalLightsCount();
    for (int lightIndex = 0; lightIndex < pixelLightCount; lightIndex++)
    {
        // 这个重载会顺带算出附加光阴影（_ADDITIONAL_LIGHT_SHADOWS）
        Light light = GetAdditionalLight(lightIndex, inputData.positionWS, shadowMask);
    #if defined(_RECEIVE_SHADOWS_OFF)
        light.shadowAttenuation = 1.0;
    #endif
        light.color *= aoFactor.directAmbientOcclusion;
        if (_LightLayers < 0.5 || IsMatchingLightLayer(GetAdditionalLightLayerMask(lightIndex), meshRenderingLayers))
            color += ClassicBlinnPhong(light, N, inputData.viewDirectionWS, albedo, specColor, shininess);
    }
#endif

#if defined(_ADDITIONAL_LIGHTS_VERTEX)
    color += inputData.vertexLighting * albedo;               // 逐顶点附加光：只有漫反射
#endif

    color += _EmissionColor.rgb;
    color = MixFog(color, inputData.fogCoord);
    fragColor = vec4(color, baseSample.a);
}
//#endregion
#endif
