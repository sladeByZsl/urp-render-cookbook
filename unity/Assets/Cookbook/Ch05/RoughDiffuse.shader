// 案例 5.7 粗糙漫反射：Oren-Nayar（定性模型）与 Minnaert
Shader "Cookbook/Ch05/RoughDiffuse"
{
    Properties
    {
        [MainColor] _BaseColor("Base Color", Color) = (0.75, 0.72, 0.68, 1)
        [KeywordEnum(Lambert, OrenNayar, Minnaert)] _Model("Model", Float) = 1
        _Roughness("Oren-Nayar Sigma (弧度)", Range(0, 1.5)) = 0.5
        _MinnaertK("Minnaert k", Range(0.3, 2)) = 0.8
        _AmbientStrength("Ambient Strength", Range(0, 1)) = 0.3
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        CBUFFER_START(UnityPerMaterial)
            half4 _BaseColor;
            float _Roughness;
            float _MinnaertK;
            half  _AmbientStrength;
        CBUFFER_END
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma shader_feature_local_fragment _MODEL_LAMBERT _MODEL_ORENNAYAR _MODEL_MINNAERT
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float3 normalWS   : TEXCOORD1;
            };

            Varyings vert(Attributes input)
            {
                Varyings output;
                VertexPositionInputs pos = GetVertexPositionInputs(input.positionOS.xyz);
                output.positionCS = pos.positionCS;
                output.positionWS = pos.positionWS;
                output.normalWS = TransformObjectToWorldNormal(input.normalOS);
                return output;
            }

            //#region orennayar
            // Oren-Nayar 定性模型，返回值已乘 N·L（URP 约定，不含 1/π）。
            // 原式 A + B·max(0, cos(φi-φr))·sinα·tanβ 里的三角函数可以全部消掉：
            //   s = L·V - (N·L)(N·V) = sinθi·sinθr·cos(φi-φr)
            //   sinα·tanβ = sinθi·sinθr / max(cosθi, cosθr)
            // 于是 cos(φi-φr)·sinα·tanβ = s / max(N·L, N·V)
            float OrenNayar(float3 N, float3 L, float3 V, float sigma)
            {
                float NdotL = saturate(dot(N, L));
                float NdotV = saturate(dot(N, V));
                float s2 = sigma * sigma;
                float A = 1.0 - 0.5 * s2 / (s2 + 0.33);
                float B = 0.45 * s2 / (s2 + 0.09);
                float s = dot(L, V) - NdotL * NdotV;
                float t = max(max(NdotL, NdotV), 1e-4);
                return NdotL * (A + B * max(0.0, s) / t);
            }
            //#endregion

            //#region minnaert
            // Minnaert：k = 1 时就是 Lambert；k < 1 边缘变亮（天鹅绒、月面感），k > 1 边缘更暗
            float Minnaert(float3 N, float3 L, float3 V, float k)
            {
                float NdotL = saturate(dot(N, L));
                float NdotV = max(saturate(dot(N, V)), 1e-3);
                return pow(NdotL, k) * pow(NdotV, k - 1.0);
            }
            //#endregion

            half4 frag(Varyings input) : SV_Target
            {
                float3 N = normalize(input.normalWS);
                float3 V = GetWorldSpaceNormalizeViewDir(input.positionWS);
                Light mainLight = GetMainLight();
                float3 L = mainLight.direction;
                half3 radiance = mainLight.color * mainLight.distanceAttenuation;

            #if defined(_MODEL_ORENNAYAR)
                float d = OrenNayar(N, L, V, _Roughness);
            #elif defined(_MODEL_MINNAERT)
                float d = Minnaert(N, L, V, _MinnaertK);
            #else
                float d = saturate(dot(N, L));
            #endif

                half3 color = _BaseColor.rgb * radiance * d;
                color += _BaseColor.rgb * SampleSH(N) * _AmbientStrength;
                return half4(color, 1);
            }
            ENDHLSL
        }

        // ---- 投影与深度：本章先照抄，原理见第 6 章 ----
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On
            ZTest LEqual
            ColorMask 0

            HLSLPROGRAM
            #pragma vertex ShadowDepthVert
            #pragma fragment ShadowDepthFrag
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Assets/Cookbook/Ch05/Ch05ShadowDepth.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On
            ColorMask R

            HLSLPROGRAM
            #pragma vertex DepthOnlyVert
            #pragma fragment DepthOnlyFrag
            #include "Assets/Cookbook/Ch05/Ch05ShadowDepth.hlsl"
            ENDHLSL
        }
    }
}
