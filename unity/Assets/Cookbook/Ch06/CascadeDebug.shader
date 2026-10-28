// 案例 6.6 级联阴影可视化：按像素所在的级联染色
Shader "Cookbook/Ch06/CascadeDebug"
{
    Properties
    {
        [MainTexture] _BaseMap("Base Map", 2D) = "white" {}
        [MainColor] _BaseColor("Base Color", Color) = (0.8, 0.8, 0.8, 1)
        _TintStrength("Tint Strength", Range(0, 1)) = 0.6
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half4  _BaseColor;
            half   _TintStrength;
        CBUFFER_END
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
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

            //#region frag
            half4 frag(Varyings input) : SV_Target
            {
                half3 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv).rgb * _BaseColor.rgb;
                half3 normalWS = normalize(input.normalWS);

                Light mainLight = GetMainLight(TransformWorldToShadowCoord(input.positionWS));
                half3 color = albedo * mainLight.color * mainLight.shadowAttenuation * saturate(dot(normalWS, mainLight.direction));
                color += albedo * SampleSH(normalWS) * 0.4;

                // ComputeCascadeIndex：依次判断像素是否落在 4 个“级联包围球”里，返回第一个命中的序号；
                // 4 表示超出了所有级联（阴影距离之外）
            #if defined(_MAIN_LIGHT_SHADOWS_CASCADE)
                half cascade = ComputeCascadeIndex(input.positionWS);
            #else
                half cascade = 0;   // 只有一个级联时 URP 不会更新包围球数据，直接当作第 0 级
            #endif
                const half3 kCascadeColors[5] =
                {
                    half3(1.0, 0.25, 0.2), half3(0.25, 0.85, 0.3), half3(0.25, 0.45, 1.0), half3(1.0, 0.85, 0.2), half3(1, 1, 1)
                };
                half3 tint = kCascadeColors[(uint)cascade];
                color = lerp(color, color * tint * 1.6, _TintStrength);
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
