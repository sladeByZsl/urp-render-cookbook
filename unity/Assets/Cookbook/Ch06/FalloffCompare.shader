// 案例 6.2 点光/聚光的衰减：URP 的平滑衰减 vs 纯平方反比 vs 线性衰减
Shader "Cookbook/Ch06/FalloffCompare"
{
    Properties
    {
        [MainTexture] _BaseMap("Base Map", 2D) = "white" {}
        [MainColor] _BaseColor("Base Color", Color) = (0.8, 0.8, 0.8, 1)
        [KeywordEnum(URP, InverseSquare, Linear)] _Falloff("Falloff", Float) = 0
        _AmbientStrength("Ambient Strength", Range(0, 1)) = 0.1
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
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _FORWARD_PLUS
            #pragma shader_feature_local_fragment _FALLOFF_URP _FALLOFF_INVERSESQUARE _FALLOFF_LINEAR
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
            };

            Varyings vert(Attributes input)
            {
                Varyings output;
                VertexPositionInputs pos = GetVertexPositionInputs(input.positionOS.xyz);
                output.positionCS = pos.positionCS;
                output.positionWS = pos.positionWS;
                output.normalWS = TransformObjectToWorldNormal(input.normalOS);
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                return output;
            }

            //#region punctual
            // 不用 GetAdditionalLight()，直接读 URP 上传的光源数组，自己算衰减。
            // URP 14 在所有平台都走常量数组（USE_STRUCTURED_BUFFER_FOR_LIGHT_DATA 恒为 0）
            half3 PunctualLight(uint loopIndex, float3 positionWS, half3 normalWS)
            {
            #if USE_FORWARD_PLUS
                int i = int(loopIndex);                       // Forward+：循环变量就是全局光源下标
            #else
                int i = GetPerObjectLightIndex(loopIndex);    // Forward：先查“本物体的第几盏灯”对应的全局下标
            #endif
                float4 lightPos   = _AdditionalLightsPosition[i];     // w = 0 表示方向光
                half3  color      = _AdditionalLightsColor[i].rgb;
                half4  attenParam = _AdditionalLightsAttenuation[i];  // x = 1/range²，zw = 聚光角度参数
                half4  spotDir    = _AdditionalLightsSpotDir[i];

                float3 lightVector = lightPos.xyz - positionWS * lightPos.w;
                float  d2 = max(dot(lightVector, lightVector), HALF_MIN);
                half3  L = half3(lightVector * rsqrt(d2));

            #if defined(_FALLOFF_INVERSESQUARE)
                float atten = rcp(d2);                                         // 物理上的平方反比，没有窗口
            #elif defined(_FALLOFF_LINEAR)
                float atten = saturate(1.0 - sqrt(d2 * attenParam.x));         // 1 - d/range
            #else
                float atten = DistanceAttenuation(d2, attenParam.xy);          // URP：平方反比 × 平滑窗口
            #endif
                atten *= AngleAttenuation(spotDir.xyz, L, attenParam.zw);      // 聚光锥；点光的参数让它恒为 1

                return color * atten * saturate(dot(normalWS, L));
            }
            //#endregion

            half4 frag(Varyings input) : SV_Target
            {
                half3 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv).rgb * _BaseColor.rgb;
                half3 normalWS = normalize(input.normalWS);

                InputData inputData = (InputData)0;
                inputData.positionWS = input.positionWS;
                inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(input.positionCS);

                Light mainLight = GetMainLight();
                half3 lighting = mainLight.color * mainLight.distanceAttenuation * saturate(dot(normalWS, mainLight.direction));

            #if defined(_ADDITIONAL_LIGHTS)
                uint lightCount = GetAdditionalLightsCount();
                #if USE_FORWARD_PLUS
                for (uint lightIndex = 0; lightIndex < min(URP_FP_DIRECTIONAL_LIGHTS_COUNT, MAX_VISIBLE_LIGHTS); lightIndex++)
                    lighting += PunctualLight(lightIndex, inputData.positionWS, normalWS);
                #endif
                LIGHT_LOOP_BEGIN(lightCount)
                    lighting += PunctualLight(lightIndex, inputData.positionWS, normalWS);
                LIGHT_LOOP_END
            #endif

                half3 color = albedo * lighting + albedo * SampleSH(normalWS) * _AmbientStrength;
                return half4(color, 1);
            }
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
