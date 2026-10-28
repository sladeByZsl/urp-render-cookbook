// 案例 23.6：自定义阴影颜色。
// 思路：不再用“阴影 = 光照乘一个 0~1 的系数”，而是在“受光色”和“阴影色”之间插值，
// 让被遮挡区域呈现指定的色相（冷色阴影、卡通紫影等），同时保留 URP 的级联、软阴影和距离淡出。
Shader "Cookbook/Ch23/ShadowColor"
{
    Properties
    {
        [MainTexture] _BaseMap ("Base Map", 2D) = "white" {}
        [MainColor]   _BaseColor ("Base Color", Color) = (1, 1, 1, 1)
        _ShadowColor ("Shadow Color (rgb=色, a=强度)", Color) = (0.25, 0.32, 0.55, 1)
        _AmbientScale ("Ambient Scale", Range(0, 2)) = 1
        [Toggle] _TintTerminator ("背光面也用阴影色", Float) = 1
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half4  _BaseColor;
            half4  _ShadowColor;
            half   _AmbientScale;
            half   _TintTerminator;
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
            #pragma multi_compile_fog
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; float2 uv : TEXCOORD0; };
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                half3  normalWS   : TEXCOORD2;
                half   fogFactor  : TEXCOORD3;
            };

            Varyings vert(Attributes input)
            {
                Varyings o;
                VertexPositionInputs p = GetVertexPositionInputs(input.positionOS.xyz);
                o.positionCS = p.positionCS;
                o.positionWS = p.positionWS;
                o.normalWS   = TransformObjectToWorldNormal(input.normalOS);
                o.uv         = TRANSFORM_TEX(input.uv, _BaseMap);
                o.fogFactor  = ComputeFogFactor(p.positionCS.z);
                return o;
            }

            //#region frag
            half4 frag(Varyings input) : SV_Target
            {
                half3 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv).rgb * _BaseColor.rgb;
                half3 normalWS = normalize(input.normalWS);

                // 逐像素求阴影坐标：同时兼容单级联 / 多级联 / 屏幕空间阴影三种关键字
                float4 shadowCoord = TransformWorldToShadowCoord(input.positionWS);
                // 带 positionWS 的重载会顺带处理“阴影距离淡出”（GetMainLightShadowFade）
                Light mainLight = GetMainLight(shadowCoord, input.positionWS, half4(1, 1, 1, 1));

                half NdotL  = saturate(dot(normalWS, mainLight.direction));
                half shadow = mainLight.shadowAttenuation;

                // lit：0 = 完全不受光，1 = 完全受光
                // _TintTerminator=1 时背光面（NdotL 小）也算“阴影”，整体风格更统一；
                // _TintTerminator=0 时只给投射阴影上色，明暗交界线保持 Lambert 的自然过渡
                half lit = _TintTerminator > 0.5 ? NdotL * shadow : shadow;
                half3 shadowTint = lerp(half3(0, 0, 0), _ShadowColor.rgb, _ShadowColor.a);
                half3 direct = lerp(shadowTint, mainLight.color, lit);
                if (_TintTerminator < 0.5) direct *= NdotL;  // 只染投射阴影时仍需要 N·L

                half3 ambient = SampleSH(normalWS) * _AmbientScale;
                half3 color = albedo * (direct + ambient);
                color = MixFog(color, input.fogFactor);
                return half4(color, 1);
            }
            //#endregion
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0
            HLSLPROGRAM
            #pragma vertex Ch23ShadowCasterVert
            #pragma fragment Ch23NullFrag
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Assets/Cookbook/Ch23/Ch23Common.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            HLSLPROGRAM
            #pragma vertex Ch23DepthOnlyVert
            #pragma fragment Ch23NullFrag
            #include "Assets/Cookbook/Ch23/Ch23Common.hlsl"
            ENDHLSL
        }
    }
}
