// 案例 5.3 Wrap Lighting：让光“绕过”明暗交界线，可选能量守恒和交界线染色
Shader "Cookbook/Ch05/WrapLighting"
{
    Properties
    {
        [MainColor] _BaseColor("Base Color", Color) = (0.85, 0.5, 0.25, 1)
        _Wrap("Wrap", Range(0, 1)) = 0.5
        [Toggle(_WRAP_ENERGY_CONSERVING)] _EnergyConserving("Energy Conserving", Float) = 0
        _TerminatorTint("Terminator Tint", Color) = (0, 0, 0, 1)
        _AmbientStrength("Ambient Strength", Range(0, 1)) = 1
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        CBUFFER_START(UnityPerMaterial)
            half4 _BaseColor;
            half  _Wrap;
            half4 _TerminatorTint;
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
            #pragma shader_feature_local_fragment _WRAP_ENERGY_CONSERVING
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

            //#region wrap
            half WrapDiffuse(half NdotL, half w)
            {
            #if defined(_WRAP_ENERGY_CONSERVING)
                // 分母 (1+w)^2：被照亮的范围变大了，峰值相应压低，总能量与 Lambert 相同
                return saturate((NdotL + w) / ((1 + w) * (1 + w)));
            #else
                // 经典写法：w = 0 时退化为 Lambert，w = 1 时等价于未平方的 Half-Lambert
                return saturate((NdotL + w) / (1 + w));
            #endif
            }
            //#endregion

            //#region frag
            half4 frag(Varyings input) : SV_Target
            {
                half3 N = normalize(input.normalWS);
                Light mainLight = GetMainLight();
                half3 radiance = mainLight.color * mainLight.distanceAttenuation;

                half NdotL = dot(N, mainLight.direction);
                half wrap = WrapDiffuse(NdotL, _Wrap);

                // 交界线染色：只在“Wrap 有、Lambert 没有”的那一圈加颜色，模拟光在皮下散射后带出的红色
                half scatter = saturate(wrap - saturate(NdotL));
                half3 diffuse = _BaseColor.rgb * radiance * wrap
                              + _TerminatorTint.rgb * radiance * scatter;

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
