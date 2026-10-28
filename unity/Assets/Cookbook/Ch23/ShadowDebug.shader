// 本章的调试 Shader：
//   _Mode = 0：按 ComputeCascadeIndex 给每一级级联上色（红/绿/蓝/黄，超出阴影距离为灰）
//   _Mode = 1：只输出主光阴影衰减（白 = 受光，黑 = 阴影），用来观察屏幕空间阴影贴图等
Shader "Cookbook/Ch23/ShadowDebug"
{
    Properties
    {
        [Enum(Cascade,0,Shadow,1)] _Mode ("Mode", Float) = 0
        _Tint ("Tint Strength", Range(0, 1)) = 0.55
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }
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

            CBUFFER_START(UnityPerMaterial)
                half _Mode;
                half _Tint;
            CBUFFER_END

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; };
            struct Varyings { float4 positionCS : SV_POSITION; float3 positionWS : TEXCOORD0; half3 normalWS : TEXCOORD1; };

            Varyings vert(Attributes v)
            {
                Varyings o;
                VertexPositionInputs p = GetVertexPositionInputs(v.positionOS.xyz);
                o.positionCS = p.positionCS; o.positionWS = p.positionWS;
                o.normalWS = TransformObjectToWorldNormal(v.normalOS);
                return o;
            }

            //#region frag
            half4 frag(Varyings i) : SV_Target
            {
                float4 shadowCoord = TransformWorldToShadowCoord(i.positionWS);
                half shadow = MainLightRealtimeShadow(shadowCoord);
                if (_Mode > 0.5) return half4(shadow.xxx, 1);

                half3 n = normalize(i.normalWS);
                Light l = GetMainLight();
                half3 shade = (saturate(dot(n, l.direction)) * shadow * 0.8 + 0.25).xxx;
                #if defined(_MAIN_LIGHT_SHADOWS_CASCADE)
                    half cascade = ComputeCascadeIndex(i.positionWS);   // 0..3，超出所有级联球为 4
                #else
                    half cascade = 0;
                #endif
                static const half3 kColors[5] =
                {
                    half3(1.0, 0.35, 0.3), half3(0.35, 0.9, 0.4), half3(0.35, 0.55, 1.0),
                    half3(1.0, 0.85, 0.3), half3(0.6, 0.6, 0.6)
                };
                half3 tint = lerp(half3(1, 1, 1), kColors[(int)cascade], _Tint);
                return half4(shade * tint, 1);
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
