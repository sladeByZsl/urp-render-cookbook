// 案例 5.8 逐顶点（Gouraud）与逐像素光照：同一套 Blinn-Phong，只是放在不同阶段算
Shader "Cookbook/Ch05/Gouraud"
{
    Properties
    {
        [MainColor] _BaseColor("Base Color", Color) = (0.75, 0.2, 0.15, 1)
        _SpecColor("Specular Color", Color) = (0.6, 0.6, 0.6, 1)
        _Shininess("Shininess", Range(1, 512)) = 96
        [Toggle(_PER_VERTEX)] _PerVertex("Per Vertex", Float) = 1
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
            #pragma shader_feature_local _PER_VERTEX
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
            #if defined(_PER_VERTEX)
                half3  color      : TEXCOORD0;   // 顶点里算好的颜色，光栅化时线性插值
            #else
                float3 positionWS : TEXCOORD0;
                float3 normalWS   : TEXCOORD1;   // 插值的是法线，到片元里再算光照
            #endif
            };

            //#region shade
            half3 ShadeBlinnPhong(float3 positionWS, float3 N)
            {
                float3 V = GetWorldSpaceNormalizeViewDir(positionWS);
                Light mainLight = GetMainLight();
                float3 L = mainLight.direction;
                half3 radiance = mainLight.color * mainLight.distanceAttenuation;
                float NdotL = dot(N, L);
                float spec = pow(saturate(dot(N, SafeNormalize(L + V))), _Shininess) * step(0.0, NdotL);
                half3 color = (_BaseColor.rgb * saturate(NdotL) + _SpecColor.rgb * spec) * radiance;
                return color + _BaseColor.rgb * SampleSH(N) * _AmbientStrength;
            }
            //#endregion

            //#region vertfrag
            Varyings vert(Attributes input)
            {
                Varyings output;
                VertexPositionInputs pos = GetVertexPositionInputs(input.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(input.normalOS);
                output.positionCS = pos.positionCS;
            #if defined(_PER_VERTEX)
                output.color = ShadeBlinnPhong(pos.positionWS, normalWS);
            #else
                output.positionWS = pos.positionWS;
                output.normalWS = normalWS;
            #endif
                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
            #if defined(_PER_VERTEX)
                return half4(input.color, 1);
            #else
                return half4(ShadeBlinnPhong(input.positionWS, normalize(input.normalWS)), 1);
            #endif
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
