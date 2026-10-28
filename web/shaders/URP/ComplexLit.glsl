// URP 的 Complex Lit 着色器（ComplexLit.shader）的 GLSL 版本：在 Lit 的基础上增加清漆（Clear Coat，_CLEARCOAT / _CLEARCOATMAP）。
// 清漆算法照抄 URP 14 的 BRDF.hlsl（InitializeBRDFDataClearCoat）、Lighting.hlsl（LightingPhysicallyBased）
// 与 GlobalIllumination.hlsl（GlobalIllumination）。其余部分与 URP/Lit.glsl 相同。
// 未移植：细节贴图（_DETAIL_MULX2/_DETAIL_SCALED）、视差贴图。
Shader "Universal Render Pipeline/Complex Lit"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" }
        GLSLINCLUDE
        #include "URP/LitInput.glsl"
        uniform float _ClearCoatMask;
        uniform float _ClearCoatSmoothness;
        uniform sampler2D _ClearCoatMap;

        // LitInput.hlsl：SampleClearCoat
        vec2 SampleClearCoat(vec2 uv)
        {
        #if defined(_CLEARCOAT) || defined(_CLEARCOATMAP)
            vec2 clearCoatMaskSmoothness = vec2(_ClearCoatMask, _ClearCoatSmoothness);
          #if defined(_CLEARCOATMAP)
            clearCoatMaskSmoothness *= texture(_ClearCoatMap, uv).rg;
          #endif
            return clearCoatMaskSmoothness;
        #else
            return vec2(0.0, 1.0);
        #endif
        }

        // ---------------- BRDF.hlsl：清漆层 BRDF ----------------
        #define CLEAR_COAT_IOR 1.5
        #define CLEAR_COAT_IETA (1.0 / CLEAR_COAT_IOR)   // 两种介质折射率之比的倒数
        float RoughnessToVariance(float roughness) { return 2.0 / (roughness * roughness) - 2.0; }
        float VarianceToRoughness(float variance) { return sqrt(2.0 / (variance + 2.0)); }
        float RoughnessToPerceptualRoughness(float roughness) { return sqrt(roughness); }
        // ConvertF0ForAirInterfaceToF0ForClearCoat15Fast：底层 F0 从“相对空气”换算成“相对 IOR 1.5 的漆”
        vec3 ConvertF0ForClearCoat15(vec3 f0) { return saturate(f0 * (f0 * 0.526868 + 0.529324) - 0.0482256); }

        void InitializeBRDFDataClearCoat(float clearCoatMask, float clearCoatSmoothness, inout BRDFData baseBRDFData, out BRDFData outBRDFData)
        {
            outBRDFData.albedo = vec3(1.0);

            // 清漆层自己的粗糙度
            outBRDFData.diffuse             = vec3(kDielectricSpec.a);   // 1 - kDielectricSpec
            outBRDFData.specular            = kDielectricSpec.rgb;
            outBRDFData.reflectivity        = kDielectricSpec.r;

            outBRDFData.perceptualRoughness = PerceptualSmoothnessToPerceptualRoughness(clearCoatSmoothness);
            outBRDFData.roughness           = max(PerceptualRoughnessToRoughness(outBRDFData.perceptualRoughness), HALF_MIN_SQRT);
            outBRDFData.roughness2          = max(outBRDFData.roughness * outBRDFData.roughness, HALF_MIN);
            outBRDFData.normalizationTerm   = outBRDFData.roughness * 4.0 + 2.0;
            outBRDFData.roughness2MinusOne  = outBRDFData.roughness2 - 1.0;
            outBRDFData.grazingTerm         = saturate(clearCoatSmoothness + kDielectricSpec.x);

            // 用清漆的 IOR 修正底层粗糙度（折射让底层高光波瓣变宽）
            float ieta               = mix(1.0, CLEAR_COAT_IETA, clearCoatMask);
            float coatRoughnessScale = ieta * ieta;
            float sigma              = RoughnessToVariance(PerceptualRoughnessToRoughness(baseBRDFData.perceptualRoughness));

            baseBRDFData.perceptualRoughness = RoughnessToPerceptualRoughness(VarianceToRoughness(sigma * coatRoughnessScale));

            // 按新的粗糙度重算底层参数
            baseBRDFData.roughness          = max(PerceptualRoughnessToRoughness(baseBRDFData.perceptualRoughness), HALF_MIN_SQRT);
            baseBRDFData.roughness2         = max(baseBRDFData.roughness * baseBRDFData.roughness, HALF_MIN);
            baseBRDFData.normalizationTerm  = baseBRDFData.roughness * 4.0 + 2.0;
            baseBRDFData.roughness2MinusOne = baseBRDFData.roughness2 - 1.0;

            // 底层 F0 换成相对漆层的值：变暗、更饱和
            baseBRDFData.specular = mix(baseBRDFData.specular, ConvertF0ForClearCoat15(baseBRDFData.specular), clearCoatMask);
        }

        BRDFData CreateClearCoatBRDFData(SurfaceData surfaceData, inout BRDFData brdfData)
        {
            BRDFData brdfDataClearCoat;
            brdfDataClearCoat.albedo = vec3(0.0); brdfDataClearCoat.diffuse = vec3(0.0); brdfDataClearCoat.specular = vec3(0.0);
            brdfDataClearCoat.reflectivity = 0.0; brdfDataClearCoat.perceptualRoughness = 0.0; brdfDataClearCoat.roughness = 0.0;
            brdfDataClearCoat.roughness2 = 0.0; brdfDataClearCoat.grazingTerm = 0.0; brdfDataClearCoat.normalizationTerm = 0.0;
            brdfDataClearCoat.roughness2MinusOne = 0.0;
        #if defined(_CLEARCOAT) || defined(_CLEARCOATMAP)
            InitializeBRDFDataClearCoat(surfaceData.clearCoatMask, surfaceData.clearCoatSmoothness, brdfData, brdfDataClearCoat);
        #endif
            return brdfDataClearCoat;
        }

        // 清漆的环境 BRDF（不含漫反射）
        vec3 EnvironmentBRDFClearCoat(BRDFData brdfData, float clearCoatMask, vec3 indirectSpecular, float fresnelTerm)
        {
            return indirectSpecular * EnvironmentBRDFSpecular(brdfData, fresnelTerm) * clearCoatMask;
        }

        // ---------------- Lighting.hlsl：带清漆的直接光 ----------------
        vec3 LightingPhysicallyBased(BRDFData brdfData, BRDFData brdfDataClearCoat,
            vec3 lightColor, vec3 lightDirectionWS, float lightAttenuation,
            vec3 normalWS, vec3 viewDirectionWS,
            float clearCoatMask, bool specularHighlightsOff)
        {
            float NdotL = saturate(dot(normalWS, lightDirectionWS));
            vec3 radiance = lightColor * (lightAttenuation * NdotL);

            vec3 brdf = brdfData.diffuse;
        #ifndef _SPECULARHIGHLIGHTS_OFF
            if (!specularHighlightsOff)
            {
                brdf += brdfData.specular * DirectBRDFSpecular(brdfData, normalWS, lightDirectionWS, viewDirectionWS);

          #if defined(_CLEARCOAT) || defined(_CLEARCOATMAP)
                // 清漆再算一次高光（F0 = 0.04 的电介质）
                float brdfCoat = kDielectricSpec.r * DirectBRDFSpecular(brdfDataClearCoat, normalWS, lightDirectionWS, viewDirectionWS);

                // 按 Khronos glTF 推荐的方式混合两层；直接光也用 NoV（与光源无关），菲涅尔用 Pow4，和 GI 保持一致
                float NoV = saturate(dot(normalWS, viewDirectionWS));
                float coatFresnel = kDielectricSpec.x + kDielectricSpec.a * Pow4(1.0 - NoV);

                brdf = brdf * (1.0 - clearCoatMask * coatFresnel) + brdfCoat * clearCoatMask;
          #endif
            }
        #endif
            return brdf * radiance;
        }
        vec3 LightingPhysicallyBased(BRDFData brdfData, BRDFData brdfDataClearCoat, Light light, vec3 normalWS, vec3 viewDirectionWS, float clearCoatMask, bool specularHighlightsOff)
        {
            return LightingPhysicallyBased(brdfData, brdfDataClearCoat, light.color, light.direction, light.distanceAttenuation * light.shadowAttenuation, normalWS, viewDirectionWS, clearCoatMask, specularHighlightsOff);
        }

        // ---------------- GlobalIllumination.hlsl：带清漆的环境光 ----------------
        vec3 GlobalIllumination(BRDFData brdfData, BRDFData brdfDataClearCoat, float clearCoatMask,
            vec3 bakedGI, float occlusion, vec3 positionWS, vec3 normalWS, vec3 viewDirectionWS)
        {
            vec3 reflectVector = reflect(-viewDirectionWS, normalWS);
            float NoV = saturate(dot(normalWS, viewDirectionWS));
            float fresnelTerm = Pow4(1.0 - NoV);

            vec3 indirectDiffuse = bakedGI;
            vec3 indirectSpecular = GlossyEnvironmentReflection(reflectVector, positionWS, brdfData.perceptualRoughness, 1.0);

            vec3 color = EnvironmentBRDF(brdfData, indirectDiffuse, indirectSpecular, fresnelTerm);

        #if defined(_CLEARCOAT) || defined(_CLEARCOATMAP)
            vec3 coatIndirectSpecular = GlossyEnvironmentReflection(reflectVector, positionWS, brdfDataClearCoat.perceptualRoughness, 1.0);
            vec3 coatColor = EnvironmentBRDFClearCoat(brdfDataClearCoat, clearCoatMask, coatIndirectSpecular, fresnelTerm);

            // 用 NoV 的菲涅尔把底层和清漆混合（glTF 推荐做法）
            float coatFresnel = kDielectricSpec.x + kDielectricSpec.a * fresnelTerm;
            return (color * (1.0 - coatFresnel * clearCoatMask) + coatColor) * occlusion;
        #else
            return color * occlusion;
        #endif
        }

        // ---------------- Lighting.hlsl：UniversalFragmentPBR（清漆版） ----------------
        // GLSL 不能和 Lighting.glsl 里同签名的 UniversalFragmentPBR 重名，这里叫 UniversalFragmentPBRComplex
        vec4 UniversalFragmentPBRComplex(InputData inputData, SurfaceData surfaceData)
        {
            bool specularHighlightsOff = false;
        #ifdef _SPECULARHIGHLIGHTS_OFF
            specularHighlightsOff = true;
        #endif
            BRDFData brdfData;
            InitializeBRDFData(surfaceData.albedo, surfaceData.metallic, surfaceData.specular, surfaceData.smoothness, surfaceData.alpha, brdfData);

            // 清漆：会顺带修改底层的 brdfData（粗糙度、F0）
            BRDFData brdfDataClearCoat = CreateClearCoatBRDFData(surfaceData, brdfData);
            AmbientOcclusionFactor ao = CreateAmbientOcclusionFactor(inputData, surfaceData);
            Light mainLight = GetMainLight(inputData.shadowCoord, inputData.positionWS, inputData.shadowMask);
            mainLight.color *= ao.directAmbientOcclusion;

            vec3 giColor = GlobalIllumination(brdfData, brdfDataClearCoat, surfaceData.clearCoatMask,
                inputData.bakedGI, ao.indirectAmbientOcclusion, inputData.positionWS, inputData.normalWS, inputData.viewDirectionWS);
            vec3 mainLightColor = LightingPhysicallyBased(brdfData, brdfDataClearCoat, mainLight,
                inputData.normalWS, inputData.viewDirectionWS, surfaceData.clearCoatMask, specularHighlightsOff);
            vec3 additional = vec3(0.0);
            for (int i = 0; i < GetAdditionalLightsCount(); i++) {
                Light light = GetAdditionalLight(i, inputData.positionWS, inputData.shadowMask);
                light.color *= ao.directAmbientOcclusion;
                additional += LightingPhysicallyBased(brdfData, brdfDataClearCoat, light,
                    inputData.normalWS, inputData.viewDirectionWS, surfaceData.clearCoatMask, specularHighlightsOff);
            }
            vec3 color = giColor + mainLightColor + additional + inputData.vertexLighting * brdfData.diffuse + surfaceData.emission;
            return vec4(color, surfaceData.alpha);
        }
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            Blend [_SrcBlend] [_DstBlend]
            ZWrite [_ZWrite]
            Cull [_Cull]
            GLSLPROGRAM
            #pragma shader_feature_local _NORMALMAP
            #pragma shader_feature_local _PARALLAXMAP
            #pragma shader_feature_local _RECEIVE_SHADOWS_OFF
            #pragma shader_feature_local_fragment _SURFACE_TYPE_TRANSPARENT
            #pragma shader_feature_local_fragment _ALPHATEST_ON
            #pragma shader_feature_local_fragment _ALPHAPREMULTIPLY_ON
            #pragma shader_feature_local_fragment _EMISSION
            #pragma shader_feature_local_fragment _METALLICSPECGLOSSMAP
            #pragma shader_feature_local_fragment _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
            #pragma shader_feature_local_fragment _OCCLUSIONMAP
            #pragma shader_feature_local_fragment _ _CLEARCOAT _CLEARCOATMAP
            #pragma shader_feature_local_fragment _SPECULARHIGHLIGHTS_OFF
            #pragma shader_feature_local_fragment _ENVIRONMENTREFLECTIONS_OFF
            #pragma shader_feature_local_fragment _SPECULAR_SETUP

            VARYING vec2 uv;
            VARYING vec3 positionWS;
            VARYING vec3 normalWS;
            VARYING vec4 tangentWS;    // w = 副切线符号
            VARYING float fogFactor;

            #ifdef VERTEX
            void main()
            {
                VertexPositionInputs vertexInput = GetVertexPositionInputs(positionOS.xyz);
                VertexNormalInputs normalInput = GetVertexNormalInputs(normalOS, tangentOS);
                uv = TransformTex(texcoord0.xy, _BaseMap_ST);
                positionWS = vertexInput.positionWS;
                normalWS = normalInput.normalWS;
                float sign = tangentOS.w * GetOddNegativeScale();
                tangentWS = vec4(normalInput.tangentWS, sign);
                fogFactor = ComputeFogFactor(vertexInput.positionCS.z);
                gl_Position = vertexInput.positionCS;
            }
            #endif

            #ifdef FRAGMENT
            void main()
            {
                SurfaceData surfaceData = InitializeStandardLitSurfaceData(uv);
            #if defined(_CLEARCOAT) || defined(_CLEARCOATMAP)
                vec2 clearCoat = SampleClearCoat(uv);
                surfaceData.clearCoatMask       = clearCoat.r;
                surfaceData.clearCoatSmoothness = clearCoat.g;
            #endif

                InputData inputData = InitInputData();
                inputData.positionWS = positionWS;
                vec3 viewDirWS = GetWorldSpaceNormalizeViewDir(positionWS);
            #ifdef _NORMALMAP
                vec3 bitangent = tangentWS.w * cross(normalWS, tangentWS.xyz);
                mat3 tangentToWorld = mat3(tangentWS.xyz, bitangent, normalWS);
                inputData.normalWS = normalize(TransformTangentToWorld(surfaceData.normalTS, tangentToWorld));
            #else
                inputData.normalWS = normalize(normalWS);
            #endif
                inputData.viewDirectionWS = viewDirWS;
            #ifdef _RECEIVE_SHADOWS_OFF
                inputData.shadowCoord = vec4(0.0);
            #else
                inputData.shadowCoord = TransformWorldToShadowCoord(positionWS);
            #endif
                inputData.fogCoord = fogFactor;
                inputData.bakedGI = SampleSH(inputData.normalWS);
                inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(gl_FragCoord);

                vec4 color = UniversalFragmentPBRComplex(inputData, surfaceData);
                color.rgb = MixFog(color.rgb, inputData.fogCoord);
            #ifndef _SURFACE_TYPE_TRANSPARENT
                color.a = 1.0;
            #endif
                fragColor = color;
            }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0
            Cull [_Cull]
            GLSLPROGRAM
            #pragma shader_feature_local_fragment _ALPHATEST_ON
            #pragma shader_feature_local_fragment _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
            VARYING vec2 uv;
            #ifdef VERTEX
            void main()
            {
                uv = TransformTex(texcoord0.xy, _BaseMap_ST);
                gl_Position = GetShadowPositionHClip(positionOS.xyz, normalOS);
            }
            #endif
            #ifdef FRAGMENT
            void main()
            {
                Alpha(SampleAlbedoAlpha(uv).a, _BaseColor, _Cutoff);
                fragColor = vec4(0.0);
            }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            Cull [_Cull]
            GLSLPROGRAM
            #pragma shader_feature_local_fragment _ALPHATEST_ON
            VARYING vec2 uv;
            #ifdef VERTEX
            void main()
            {
                uv = TransformTex(texcoord0.xy, _BaseMap_ST);
                gl_Position = TransformObjectToHClip(positionOS.xyz);
            }
            #endif
            #ifdef FRAGMENT
            void main()
            {
                Alpha(SampleAlbedoAlpha(uv).a, _BaseColor, _Cutoff);
                fragColor = vec4(gl_FragCoord.z);
            }
            #endif
            ENDGLSL
        }

        // URP 里这个 Pass 叫 DepthNormalsOnly；网页版沿用 Lit.glsl 的 DepthNormals，便于 SSAO 等公共模块统一处理
        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode"="DepthNormals" }
            ZWrite On
            Cull [_Cull]
            GLSLPROGRAM
            #pragma shader_feature_local _NORMALMAP
            #pragma shader_feature_local_fragment _ALPHATEST_ON
            VARYING vec2 uv;
            VARYING vec3 normalWS;
            VARYING vec4 tangentWS;
            #ifdef VERTEX
            void main()
            {
                uv = TransformTex(texcoord0.xy, _BaseMap_ST);
                VertexNormalInputs n = GetVertexNormalInputs(normalOS, tangentOS);
                normalWS = n.normalWS;
                tangentWS = vec4(n.tangentWS, tangentOS.w * GetOddNegativeScale());
                gl_Position = TransformObjectToHClip(positionOS.xyz);
            }
            #endif
            #ifdef FRAGMENT
            void main()
            {
                Alpha(SampleAlbedoAlpha(uv).a, _BaseColor, _Cutoff);
            #ifdef _NORMALMAP
                vec3 nTS = SampleNormal(uv, _BumpScale);
                vec3 b = tangentWS.w * cross(normalWS, tangentWS.xyz);
                vec3 n = normalize(mat3(tangentWS.xyz, b, normalWS) * nTS);
            #else
                vec3 n = normalize(normalWS);
            #endif
                fragColor = vec4(n, 0.0);
            }
            #endif
            ENDGLSL
        }
    }
}
