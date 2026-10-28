// 案例 6.1 多光源 Lambert：主光 + 附加光循环，同时支持 Forward 与 Forward+
Shader "Cookbook/Ch06/MultiLightLambert"
{
    Properties
    {
        [MainTexture] _BaseMap("Base Map", 2D) = "white" {}
        [MainColor] _BaseColor("Base Color", Color) = (0.8, 0.8, 0.8, 1)
        _AmbientStrength("Ambient Strength", Range(0, 1)) = 0.3
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half4  _BaseColor;
            half   _AmbientStrength;
        CBUFFER_END
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            //#region keywords
            // Forward 路径：URP 按 Asset 的“Additional Lights”设置打开 _ADDITIONAL_LIGHTS（逐像素）
            // 或 _ADDITIONAL_LIGHTS_VERTEX（逐顶点）；Forward+ 路径打开 _FORWARD_PLUS，
            // Core.hlsl 会据此自动定义 _ADDITIONAL_LIGHTS 和 USE_FORWARD_PLUS
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _FORWARD_PLUS
            //#endregion

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS   : TEXCOORD2;
            #if defined(_ADDITIONAL_LIGHTS_VERTEX)
                half3  vertexLight : TEXCOORD3;
            #endif
            };

            Varyings vert(Attributes input)
            {
                Varyings output;
                VertexPositionInputs pos = GetVertexPositionInputs(input.positionOS.xyz);
                output.positionCS = pos.positionCS;
                output.positionWS = pos.positionWS;
                output.normalWS = TransformObjectToWorldNormal(input.normalOS);
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
            #if defined(_ADDITIONAL_LIGHTS_VERTEX)
                // 逐顶点模式：URP 的 VertexLighting() 在顶点里把所有附加光的 Lambert 累加好
                output.vertexLight = VertexLighting(pos.positionWS, output.normalWS);
            #endif
                return output;
            }

            half3 LambertLight(Light light, half3 normalWS)
            {
                half3 radiance = light.color * (light.distanceAttenuation * light.shadowAttenuation);
                return radiance * saturate(dot(normalWS, light.direction));
            }

            //#region frag
            half4 frag(Varyings input) : SV_Target
            {
                half3 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv).rgb * _BaseColor.rgb;
                half3 normalWS = normalize(input.normalWS);

                // LIGHT_LOOP_BEGIN 在 Forward+ 下会直接读取名为 inputData 的变量
                // （inputData.positionWS 与 inputData.normalizedScreenSpaceUV），所以名字不能改
                InputData inputData = (InputData)0;
                inputData.positionWS = input.positionWS;
                inputData.normalWS = normalWS;
                inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(input.positionCS);

                // 主光源
                half3 lighting = LambertLight(GetMainLight(), normalWS);

            #if defined(_ADDITIONAL_LIGHTS)
                uint lightCount = GetAdditionalLightsCount();   // Forward+ 下恒为 0，循环靠 cluster 迭代器

                #if USE_FORWARD_PLUS
                // Forward+：附加的“方向光”不进入分簇结构，排在光源数组最前面，要单独循环
                for (uint lightIndex = 0; lightIndex < min(URP_FP_DIRECTIONAL_LIGHTS_COUNT, MAX_VISIBLE_LIGHTS); lightIndex++)
                {
                    lighting += LambertLight(GetAdditionalLight(lightIndex, inputData.positionWS), normalWS);
                }
                #endif

                // Forward：for (lightIndex = 0; lightIndex < lightCount; ...)
                // Forward+：遍历当前像素所在 tile 与 z-bin 的光源位掩码
                LIGHT_LOOP_BEGIN(lightCount)
                    Light light = GetAdditionalLight(lightIndex, inputData.positionWS);
                    lighting += LambertLight(light, normalWS);
                LIGHT_LOOP_END
            #endif

            #if defined(_ADDITIONAL_LIGHTS_VERTEX)
                lighting += input.vertexLight;
            #endif

                half3 color = albedo * lighting + albedo * SampleSH(normalWS) * _AmbientStrength;
                return half4(color, 1);
            }
            //#endregion
            ENDHLSL
        }

        // ---- 投影与深度：见案例 6.4 与 6.8 ----
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On
            ZTest LEqual
            ColorMask 0

            HLSLPROGRAM
            #pragma vertex ShadowCasterVertex
            #pragma fragment ShadowCasterFragment
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Assets/Cookbook/Ch06/ShadowCasterPass.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On
            ColorMask R

            HLSLPROGRAM
            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment
            #include "Assets/Cookbook/Ch06/DepthOnlyPass.hlsl"
            ENDHLSL
        }
    }
}
