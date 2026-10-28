// 案例 5.1 Lambert 漫反射：只计算主光源的 N·L，再加一点球谐环境光
Shader "Cookbook/Ch05/Lambert"
{
    Properties
    {
        [MainColor] _BaseColor("Base Color", Color) = (0.85, 0.5, 0.25, 1)
        _AmbientStrength("Ambient Strength", Range(0, 1)) = 1
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        CBUFFER_START(UnityPerMaterial)
            half4 _BaseColor;
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
                // 法线要用“逆转置矩阵”变换，TransformObjectToWorldNormal 已经处理了非等比缩放
                output.normalWS = TransformObjectToWorldNormal(input.normalOS);
                return output;
            }

            //#region frag
            half4 frag(Varyings input) : SV_Target
            {
                // 插值后的法线长度不再是 1，必须重新归一化
                half3 N = normalize(input.normalWS);

                Light mainLight = GetMainLight();
                // direction 指向光源；color 已经乘过 Intensity，是线性空间的 HDR 值
                half3 radiance = mainLight.color * mainLight.distanceAttenuation;

                // 余弦定律：背光面 N·L < 0，必须截断到 0，否则会“吸收”别的光
                half NdotL = saturate(dot(N, mainLight.direction));
                half3 diffuse = _BaseColor.rgb * radiance * NdotL;

                // 环境光：来自天空的球谐光照，第 8 章细讲。没有它，背光面会是纯黑
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
