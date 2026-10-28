// 案例 5.9 经典光照实验台：用关键字自由组合漫反射模型与高光模型
Shader "Cookbook/Ch05/ClassicLab"
{
    Properties
    {
        [MainTexture] _BaseMap("Base Map", 2D) = "white" {}
        [MainColor] _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        [KeywordEnum(Lambert, HalfLambert, Wrap, OrenNayar)] _Diffuse("Diffuse Model", Float) = 0
        [KeywordEnum(None, Phong, BlinnPhong)] _Specular("Specular Model", Float) = 2
        _Wrap("Wrap", Range(0, 1)) = 0.5
        _Roughness("Oren-Nayar Sigma", Range(0, 1.5)) = 0.5
        _SpecColor("Specular Color", Color) = (0.2, 0.2, 0.2, 1)
        _Smoothness("Smoothness", Range(0, 1)) = 0.6
        _AmbientStrength("Ambient Strength", Range(0, 1)) = 1
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half4  _BaseColor;
            half   _Wrap;
            half   _Roughness;
            half4  _SpecColor;
            half   _Smoothness;
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
            #pragma shader_feature_local_fragment _DIFFUSE_LAMBERT _DIFFUSE_HALFLAMBERT _DIFFUSE_WRAP _DIFFUSE_ORENNAYAR
            #pragma shader_feature_local_fragment _SPECULAR_NONE _SPECULAR_PHONG _SPECULAR_BLINNPHONG
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Assets/Cookbook/Ch05/ClassicLighting.hlsl"

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

            //#region frag
            half4 frag(Varyings input) : SV_Target
            {
                half3 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv).rgb * _BaseColor.rgb;
                float3 N = normalize(input.normalWS);
                float3 V = GetWorldSpaceNormalizeViewDir(input.positionWS);
                Light mainLight = GetMainLight();
                float3 L = mainLight.direction;
                half3 radiance = mainLight.color * mainLight.distanceAttenuation;

            #if defined(_DIFFUSE_HALFLAMBERT)
                float d = DiffuseHalfLambert(N, L, 2.0);
            #elif defined(_DIFFUSE_WRAP)
                float d = DiffuseWrap(N, L, _Wrap);
            #elif defined(_DIFFUSE_ORENNAYAR)
                float d = DiffuseOrenNayar(N, L, V, _Roughness);
            #else
                float d = DiffuseLambert(N, L);
            #endif

                float n = ShininessFromSmoothness(_Smoothness);
            #if defined(_SPECULAR_PHONG)
                float s = SpecularPhong(N, L, V, n);
            #elif defined(_SPECULAR_BLINNPHONG)
                float s = SpecularBlinnPhong(N, L, V, n);
            #else
                float s = 0.0;
            #endif

                half3 color = (albedo * d + _SpecColor.rgb * s) * radiance;
                color += albedo * SampleSH(N) * _AmbientStrength;
                return half4(color, 1);
            }
            //#endregion
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
