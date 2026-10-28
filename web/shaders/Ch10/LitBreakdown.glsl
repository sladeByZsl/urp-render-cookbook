// 第 10 章：把 URP Lit 的光照拆开看。（GLSL 版，对应 Ch10/LitBreakdown.shader）
// 按 UniversalFragmentPBR 的流程逐项重算，但把四个分量分开累加：
//   直接漫反射 / 直接高光 / 间接漫反射（SH）/ 间接高光（反射探针），
// 用 _Component 选择输出哪一项。Full 模式直接调用 URP 原函数，Sum 模式输出四项之和，两者应当一致。
Shader "Cookbook/Ch10/LitBreakdown"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        // 写在 GLSLINCLUDE 里的内容会拼到本 SubShader 每个 Pass 的最前面，三个 Pass 的 uniform 自然一致
        uniform vec4  _BaseMap_ST;
        uniform vec4  _BaseColor;
        uniform vec4  _EmissionColor;
        uniform float _Cutoff;
        uniform float _Metallic;
        uniform float _Smoothness;
        uniform float _BumpScale;
        uniform float _Component;

        // ---- SurfaceInput.hlsl 的贴图与采样函数 ----
        uniform sampler2D _BaseMap;
        uniform sampler2D _BumpMap;
        vec4 SampleAlbedoAlpha(vec2 uv) { return texture(_BaseMap, uv); }
        float Alpha(float albedoAlpha, vec4 color, float cutoff)
        {
            float alpha = albedoAlpha * color.a;
        #ifdef _ALPHATEST_ON
            if (alpha - cutoff < 0.0) discard;
        #endif
            return alpha;
        }
        vec3 SampleNormal(vec2 uv, float scale)
        {
        #ifdef _NORMALMAP
            return UnpackNormalScale(texture(_BumpMap, uv), scale);
        #else
            return vec3(0.0, 0.0, 1.0);
        #endif
        }
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            GLSLPROGRAM
            #pragma shader_feature_local _NORMALMAP
            // 管线关键字（阴影、附加光、SSAO）网页版引擎始终提供；Forward+、反射探针混合、Instancing 网页版没有

            VARYING vec2 uv;
            VARYING vec3 positionWS;
            VARYING vec3 normalWS;
            VARYING vec4 tangentWS;

            #ifdef VERTEX
            void main()
            {
                VertexPositionInputs pos = GetVertexPositionInputs(positionOS.xyz);
                VertexNormalInputs nrm = GetVertexNormalInputs(normalOS, tangentOS);
                gl_Position = pos.positionCS; positionWS = pos.positionWS;
                normalWS = nrm.normalWS;
                tangentWS = vec4(nrm.tangentWS, tangentOS.w * GetOddNegativeScale());
                uv = TransformTex(texcoord0.xy, _BaseMap_ST);
            }
            #endif

            #ifdef FRAGMENT
            void BuildData(out SurfaceData s, out InputData d)
            {
                s = InitSurfaceData();
                s.albedo = SampleAlbedoAlpha(uv).rgb * _BaseColor.rgb;
                s.alpha = 1.0; s.metallic = _Metallic; s.smoothness = _Smoothness; s.occlusion = 1.0;
                s.normalTS = SampleNormal(uv, _BumpScale);
                s.emission = _EmissionColor.rgb;

                d = InitInputData();
                d.positionWS = positionWS; d.positionCS = gl_FragCoord;
            #if defined(_NORMALMAP)
                vec3 bitangent = tangentWS.w * cross(normalWS, tangentWS.xyz);
                d.normalWS = TransformTangentToWorld(s.normalTS, mat3(tangentWS.xyz, bitangent, normalWS));
            #else
                d.normalWS = normalWS;
            #endif
                d.normalWS = NormalizeNormalPerPixel(d.normalWS);
                d.viewDirectionWS = GetWorldSpaceNormalizeViewDir(positionWS);
                d.shadowCoord = TransformWorldToShadowCoord(positionWS);
                d.bakedGI = SampleSH(d.normalWS);
                d.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(gl_FragCoord);
                d.shadowMask = vec4(1.0);
            }

            // URP Lighting.hlsl 里 GetMainLight(inputData, shadowMask, aoFactor) / GetAdditionalLight(i, inputData, shadowMask, aoFactor)
            // 这两个重载的 GLSL 写法：取灯 + 按 SSAO 的 Direct Lighting Strength 压一点直接光（没开 SSAO 时 directAmbientOcclusion = 1）
            Light GetMainLight(InputData inputData, vec4 shadowMask, AmbientOcclusionFactor aoFactor)
            {
                Light light = GetMainLight(inputData.shadowCoord, inputData.positionWS, shadowMask);
                light.color *= aoFactor.directAmbientOcclusion;
                return light;
            }
            Light GetAdditionalLight(int i, InputData inputData, vec4 shadowMask, AmbientOcclusionFactor aoFactor)
            {
                Light light = GetAdditionalLight(i, inputData.positionWS, shadowMask);
                light.color *= aoFactor.directAmbientOcclusion;
                return light;
            }

            //#region direct
            // 与 LightingPhysicallyBased 相同的计算，只是把漫反射和高光分开累加
            void AccumulateDirect(BRDFData brdf, Light light, InputData inputData, inout vec3 diffuse, inout vec3 specular)
            {
                float NdotL = saturate(dot(inputData.normalWS, light.direction));
                vec3 radiance = light.color * (light.distanceAttenuation * light.shadowAttenuation * NdotL);
                diffuse  += brdf.diffuse * radiance;
                specular += brdf.specular * DirectBRDFSpecular(brdf, inputData.normalWS, light.direction, inputData.viewDirectionWS) * radiance;
            }
            //#endregion

            void main()
            {
                SurfaceData surfaceData; InputData inputData;
                BuildData(surfaceData, inputData);

                if (_Component < 0.5)
                {
                    fragColor = UniversalFragmentPBR(inputData, surfaceData);   // 原版，作为对照
                    return;
                }

                //#region breakdown
                BRDFData brdf;
                InitializeBRDFData(surfaceData.albedo, surfaceData.metallic, surfaceData.specular, surfaceData.smoothness, surfaceData.alpha, brdf);
                vec4 shadowMask = vec4(1.0);   // CalculateShadowMask：没有 Shadowmask 时是 1
                AmbientOcclusionFactor aoFactor = CreateAmbientOcclusionFactor(inputData, surfaceData);
                Light mainLight = GetMainLight(inputData, shadowMask, aoFactor);
                // MixRealtimeAndBakedGI：没有光照贴图时什么都不做

                // ---- 间接光：与 GlobalIllumination() 相同，只是拆成两项 ----
                vec3 reflectVector = reflect(-inputData.viewDirectionWS, inputData.normalWS);
                float NoV = saturate(dot(inputData.normalWS, inputData.viewDirectionWS));
                float fresnelTerm = Pow4(1.0 - NoV);
                vec3 envSpecular = GlossyEnvironmentReflection(reflectVector, inputData.positionWS,
                                        brdf.perceptualRoughness, 1.0);
                vec3 indirectDiffuse  = inputData.bakedGI * brdf.diffuse * aoFactor.indirectAmbientOcclusion;
                vec3 indirectSpecular = envSpecular * EnvironmentBRDFSpecular(brdf, fresnelTerm) * aoFactor.indirectAmbientOcclusion;

                // ---- 直接光：主光 + 附加光 ----
                vec3 directDiffuse = vec3(0.0), directSpecular = vec3(0.0);
                AccumulateDirect(brdf, mainLight, inputData, directDiffuse, directSpecular);

                // 网页版只有 Forward：附加光就是普通循环（HLSL 版的 Forward+ 分支与 LIGHT_LOOP_BEGIN 宏不需要）
                int pixelLightCount = GetAdditionalLightsCount();
                for (int lightIndex = 0; lightIndex < pixelLightCount; lightIndex++)
                {
                    Light light = GetAdditionalLight(lightIndex, inputData, shadowMask, aoFactor);
                    AccumulateDirect(brdf, light, inputData, directDiffuse, directSpecular);
                }
                //#endregion

                vec3 c;
                if      (_Component < 1.5) c = directDiffuse;
                else if (_Component < 2.5) c = directSpecular;
                else if (_Component < 3.5) c = indirectDiffuse;
                else if (_Component < 4.5) c = indirectSpecular;
                else if (_Component < 5.5) c = directDiffuse + directSpecular + indirectDiffuse + indirectSpecular + surfaceData.emission;
                else                       c = vec3(mainLight.shadowAttenuation);
                fragColor = vec4(c, 1.0);
            }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0
            GLSLPROGRAM
            // URP 的 ShadowCasterPass.hlsl（GLSL 写法）
            VARYING vec2 uv;
            #ifdef VERTEX
            void main()   // ShadowPassVertex
            {
                uv = TransformTex(texcoord0.xy, _BaseMap_ST);
                gl_Position = GetShadowPositionHClip(positionOS.xyz, normalOS);
            }
            #endif
            #ifdef FRAGMENT
            void main()   // ShadowPassFragment
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
            GLSLPROGRAM
            // URP 的 DepthOnlyPass.hlsl（GLSL 写法）
            VARYING vec2 uv;
            #ifdef VERTEX
            void main()   // DepthOnlyVertex
            {
                uv = TransformTex(texcoord0.xy, _BaseMap_ST);
                gl_Position = TransformObjectToHClip(positionOS.xyz);
            }
            #endif
            #ifdef FRAGMENT
            void main()   // DepthOnlyFragment
            {
                Alpha(SampleAlbedoAlpha(uv).a, _BaseColor, _Cutoff);
                fragColor = vec4(gl_FragCoord.z);
            }
            #endif
            ENDGLSL
        }
    }
}
