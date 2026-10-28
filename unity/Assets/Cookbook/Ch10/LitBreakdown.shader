// 第 10 章：把 URP Lit 的光照拆开看。
// 按 UniversalFragmentPBR 的流程逐项重算，但把四个分量分开累加：
//   直接漫反射 / 直接高光 / 间接漫反射（SH）/ 间接高光（反射探针），
// 用 _Component 选择输出哪一项。Full 模式直接调用 URP 原函数，Sum 模式输出四项之和，两者应当一致。
Shader "Cookbook/Ch10/LitBreakdown"
{
    Properties
    {
        [Enum(Full_URP,0,DirectDiffuse,1,DirectSpecular,2,IndirectDiffuse,3,IndirectSpecular,4,Sum,5,MainShadow,6)]
        _Component("Component", Float) = 0
        [MainTexture] _BaseMap("Base Map", 2D) = "white" {}
        [MainColor] _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        _Metallic("Metallic", Range(0, 1)) = 0
        _Smoothness("Smoothness", Range(0, 1)) = 0.5
        [Normal][NoScaleOffset] _BumpMap("Normal Map", 2D) = "bump" {}
        _BumpScale("Normal Scale", Float) = 1
        [HDR] _EmissionColor("Emission", Color) = (0, 0, 0, 1)
        [HideInInspector] _Cutoff("Alpha Cutoff", Range(0, 1)) = 0.5
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        // 写在 HLSLINCLUDE 里的内容会拼到本 SubShader 每个 Pass 的最前面，三个 Pass 的 CBUFFER 自然一致
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/SurfaceInput.hlsl"
        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half4  _BaseColor;
            half4  _EmissionColor;
            half   _Cutoff;
            half   _Metallic;
            half   _Smoothness;
            half   _BumpScale;
            half   _Component;
        CBUFFER_END
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma target 2.0
            #pragma vertex vert
            #pragma fragment frag
            #pragma shader_feature_local _NORMALMAP
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BLENDING
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BOX_PROJECTION
            #pragma multi_compile_fragment _ _SCREEN_SPACE_OCCLUSION
            #pragma multi_compile _ _FORWARD_PLUS
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION; float3 normalOS : NORMAL; float4 tangentOS : TANGENT; float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            struct Varyings
            {
                float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; float3 positionWS : TEXCOORD1;
                half3 normalWS : TEXCOORD2; half4 tangentWS : TEXCOORD3;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            Varyings vert(Attributes v)
            {
                Varyings o = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, o);
                VertexPositionInputs pos = GetVertexPositionInputs(v.positionOS.xyz);
                VertexNormalInputs nrm = GetVertexNormalInputs(v.normalOS, v.tangentOS);
                o.positionCS = pos.positionCS; o.positionWS = pos.positionWS;
                o.normalWS = nrm.normalWS;
                o.tangentWS = half4(nrm.tangentWS, v.tangentOS.w * GetOddNegativeScale());
                o.uv = TRANSFORM_TEX(v.uv, _BaseMap);
                return o;
            }

            void BuildData(Varyings i, out SurfaceData s, out InputData d)
            {
                s = (SurfaceData)0;
                s.albedo = SampleAlbedoAlpha(i.uv, TEXTURE2D_ARGS(_BaseMap, sampler_BaseMap)).rgb * _BaseColor.rgb;
                s.alpha = 1; s.metallic = _Metallic; s.smoothness = _Smoothness; s.occlusion = 1;
                s.normalTS = SampleNormal(i.uv, TEXTURE2D_ARGS(_BumpMap, sampler_BumpMap), _BumpScale);
                s.emission = _EmissionColor.rgb;

                d = (InputData)0;
                d.positionWS = i.positionWS; d.positionCS = i.positionCS;
            #if defined(_NORMALMAP)
                float3 bitangent = i.tangentWS.w * cross(i.normalWS, i.tangentWS.xyz);
                d.normalWS = TransformTangentToWorld(s.normalTS, half3x3(i.tangentWS.xyz, bitangent, i.normalWS));
            #else
                d.normalWS = i.normalWS;
            #endif
                d.normalWS = NormalizeNormalPerPixel(d.normalWS);
                d.viewDirectionWS = GetWorldSpaceNormalizeViewDir(i.positionWS);
                d.shadowCoord = TransformWorldToShadowCoord(i.positionWS);
                d.bakedGI = SampleSH(d.normalWS);
                d.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(i.positionCS);
                d.shadowMask = half4(1, 1, 1, 1);
            }

            //#region direct
            // 与 LightingPhysicallyBased 相同的计算，只是把漫反射和高光分开累加
            void AccumulateDirect(BRDFData brdf, Light light, InputData inputData, inout half3 diffuse, inout half3 specular)
            {
                half NdotL = saturate(dot(inputData.normalWS, light.direction));
                half3 radiance = light.color * (light.distanceAttenuation * light.shadowAttenuation * NdotL);
                diffuse  += brdf.diffuse * radiance;
                specular += brdf.specular * DirectBRDFSpecular(brdf, inputData.normalWS, light.direction, inputData.viewDirectionWS) * radiance;
            }
            //#endregion

            half4 frag(Varyings i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                SurfaceData surfaceData; InputData inputData;
                BuildData(i, surfaceData, inputData);

                if (_Component < 0.5)
                    return UniversalFragmentPBR(inputData, surfaceData);   // 原版，作为对照

                //#region breakdown
                BRDFData brdf;
                InitializeBRDFData(surfaceData, brdf);
                half4 shadowMask = CalculateShadowMask(inputData);
                AmbientOcclusionFactor aoFactor = CreateAmbientOcclusionFactor(inputData, surfaceData);
                Light mainLight = GetMainLight(inputData, shadowMask, aoFactor);
                MixRealtimeAndBakedGI(mainLight, inputData.normalWS, inputData.bakedGI);

                // ---- 间接光：与 GlobalIllumination() 相同，只是拆成两项 ----
                half3 reflectVector = reflect(-inputData.viewDirectionWS, inputData.normalWS);
                half NoV = saturate(dot(inputData.normalWS, inputData.viewDirectionWS));
                half fresnelTerm = Pow4(1.0 - NoV);
                half3 envSpecular = GlossyEnvironmentReflection(reflectVector, inputData.positionWS,
                                        brdf.perceptualRoughness, 1.0h, inputData.normalizedScreenSpaceUV);
                half3 indirectDiffuse  = inputData.bakedGI * brdf.diffuse * aoFactor.indirectAmbientOcclusion;
                half3 indirectSpecular = envSpecular * EnvironmentBRDFSpecular(brdf, fresnelTerm) * aoFactor.indirectAmbientOcclusion;

                // ---- 直接光：主光 + 附加光 ----
                half3 directDiffuse = 0, directSpecular = 0;
                AccumulateDirect(brdf, mainLight, inputData, directDiffuse, directSpecular);

            #if defined(_ADDITIONAL_LIGHTS)
                uint pixelLightCount = GetAdditionalLightsCount();
            #if USE_FORWARD_PLUS
                // Forward+ 下，附加的“方向光”不进分簇列表，要单独循环
                for (uint lightIndex = 0; lightIndex < min(URP_FP_DIRECTIONAL_LIGHTS_COUNT, MAX_VISIBLE_LIGHTS); lightIndex++)
                {
                    Light light = GetAdditionalLight(lightIndex, inputData, shadowMask, aoFactor);
                    AccumulateDirect(brdf, light, inputData, directDiffuse, directSpecular);
                }
            #endif
                // 注意：Forward+ 版本的 LIGHT_LOOP_BEGIN 宏内部直接引用名为 inputData 的变量
                LIGHT_LOOP_BEGIN(pixelLightCount)
                    Light light = GetAdditionalLight(lightIndex, inputData, shadowMask, aoFactor);
                    AccumulateDirect(brdf, light, inputData, directDiffuse, directSpecular);
                LIGHT_LOOP_END
            #endif
                //#endregion

                half3 c;
                if      (_Component < 1.5) c = directDiffuse;
                else if (_Component < 2.5) c = directSpecular;
                else if (_Component < 3.5) c = indirectDiffuse;
                else if (_Component < 4.5) c = indirectSpecular;
                else if (_Component < 5.5) c = directDiffuse + directSpecular + indirectDiffuse + indirectSpecular + surfaceData.emission;
                else                       c = mainLight.shadowAttenuation.xxx;
                return half4(c, 1);
            }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0
            HLSLPROGRAM
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment
            #pragma multi_compile_instancing
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            HLSLPROGRAM
            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment
            #pragma multi_compile_instancing
            #include "Packages/com.unity.render-pipelines.universal/Shaders/DepthOnlyPass.hlsl"
            ENDHLSL
        }
    }
}
