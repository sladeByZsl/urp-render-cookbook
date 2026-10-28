// 案例 5.6 高光归一化：让高光指数只改变“形状”，不改变“总能量”
Shader "Cookbook/Ch05/SpecularNormalized"
{
    Properties
    {
        [MainColor] _BaseColor("Base Color", Color) = (0.08, 0.08, 0.09, 1)
        _SpecColor("Specular Color", Color) = (0.25, 0.25, 0.25, 1)
        _Shininess("Shininess", Range(1, 2048)) = 128
        [KeywordEnum(BlinnPhong, Phong)] _Model("Model", Float) = 0
        [Toggle(_NORMALIZE_SPECULAR)] _Normalize("Normalize", Float) = 1
        _AmbientStrength("Ambient Strength", Range(0, 1)) = 1
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        CBUFFER_START(UnityPerMaterial)
            half4 _BaseColor;
            half4 _SpecColor;
            float _Shininess;
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
            #pragma shader_feature_local_fragment _MODEL_BLINNPHONG _MODEL_PHONG
            #pragma shader_feature_local_fragment _NORMALIZE_SPECULAR
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

            //#region spec
            // 返回“乘上 N·L 之后”的高光项，与 URP 的约定一致：漫反射写成 albedo * N·L（没有 1/π），
            // 所以这里的归一化系数也整体乘了 π：Blinn-Phong 用 (n+8)/8，Phong 用 (n+2)/2
            float SpecularTerm(float3 N, float3 L, float3 V, float n)
            {
                float NdotL = saturate(dot(N, L));
            #if defined(_MODEL_PHONG)
                float lobe = pow(saturate(dot(reflect(-L, N), V)), n);
                float norm = (n + 2.0) / 2.0;
            #else
                float lobe = pow(saturate(dot(N, SafeNormalize(L + V))), n);
                float norm = (n + 8.0) / 8.0;
            #endif
            #if !defined(_NORMALIZE_SPECULAR)
                norm = 1.0;
            #endif
                return norm * lobe * NdotL;
            }
            //#endregion

            half4 frag(Varyings input) : SV_Target
            {
                float3 N = normalize(input.normalWS);
                float3 V = GetWorldSpaceNormalizeViewDir(input.positionWS);
                Light mainLight = GetMainLight();
                float3 L = mainLight.direction;
                half3 radiance = mainLight.color * mainLight.distanceAttenuation;

                half3 diffuse = _BaseColor.rgb * saturate(dot(N, L));
                half3 specular = _SpecColor.rgb * SpecularTerm(N, L, V, _Shininess);

                half3 color = (diffuse + specular) * radiance;
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
