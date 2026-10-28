// 案例 5.2 Half-Lambert：把 [-1,1] 的 N·L 线性映射到 [0,1]，再可选地做一次幂
Shader "Cookbook/Ch05/HalfLambert"
{
    Properties
    {
        [MainColor] _BaseColor("Base Color", Color) = (0.85, 0.5, 0.25, 1)
        _Power("Power (1 = 线性, 2 = Valve 原版)", Range(1, 4)) = 2
        _AmbientStrength("Ambient Strength", Range(0, 1)) = 1
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        CBUFFER_START(UnityPerMaterial)
            half4 _BaseColor;
            half  _Power;
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
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 normalWS   : TEXCOORD0;
            };

            Varyings vert(Attributes input)
            {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.normalWS = TransformObjectToWorldNormal(input.normalOS);
                return output;
            }

            //#region frag
            half4 frag(Varyings input) : SV_Target
            {
                half3 N = normalize(input.normalWS);
                Light mainLight = GetMainLight();
                half3 radiance = mainLight.color * mainLight.distanceAttenuation;

                // 注意这里没有 saturate：背光面的负值也要参与映射
                half NdotL = dot(N, mainLight.direction);
                half halfLambert = NdotL * 0.5 + 0.5;          // [-1,1] -> [0,1]
                halfLambert = pow(halfLambert, _Power);         // Valve 原版取平方，让暗部重新“沉下去”

                half3 diffuse = _BaseColor.rgb * radiance * halfLambert;
                half3 ambient = _BaseColor.rgb * SampleSH(N) * _AmbientStrength;
                return half4(diffuse + ambient, 1);
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
