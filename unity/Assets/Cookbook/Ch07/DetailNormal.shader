// 基础法线 + 细节法线，四种混合方法可切换（演示用；实际项目里选定一种写死即可）。
Shader "Cookbook/Ch07/DetailNormal"
{
    Properties
    {
        [MainTexture] _BaseMap("Albedo", 2D) = "white" {}
        [NoScaleOffset][Normal] _BumpMap("Base Normal", 2D) = "bump" {}
        _BumpScale("Base Scale", Range(0, 3)) = 1
        [Normal] _DetailNormalMap("Detail Normal", 2D) = "bump" {}
        _DetailNormalScale("Detail Scale", Range(0, 3)) = 1
        _DetailMask("Detail Mask (0~1)", Range(0, 1)) = 1
        [Enum(Linear,0,UDN,1,Whiteout,2,RNM,3,BaseOnly,4,DetailOnly,5)] _BlendMode("Blend Mode", Float) = 3
        [Toggle] _ShowNormal("Show Normal As Color", Float) = 0
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            float4 _DetailNormalMap_ST;
            half _BumpScale;
            half _DetailNormalScale;
            half _DetailMask;
            half _BlendMode;
            half _ShowNormal;
        CBUFFER_END
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #include "Assets/Cookbook/Ch07/Ch07Common.hlsl"
            #include "Assets/Cookbook/Ch07/NormalBlend.hlsl"

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);
            TEXTURE2D(_BumpMap); SAMPLER(sampler_BumpMap);
            TEXTURE2D(_DetailNormalMap); SAMPLER(sampler_DetailNormalMap);

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; float4 tangentOS : TANGENT; float2 uv : TEXCOORD0; };
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float4 uv         : TEXCOORD0;   // xy 基础 UV，zw 细节 UV（细节贴图通常平铺得更密）
                float3 positionWS : TEXCOORD1;
                float3 normalWS   : TEXCOORD2;
                half4  tangentWS  : TEXCOORD3;
            };

            Varyings vert(Attributes input)
            {
                Varyings o;
                VertexPositionInputs pos = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs nrm = GetVertexNormalInputs(input.normalOS, input.tangentOS);
                o.positionCS = pos.positionCS;
                o.positionWS = pos.positionWS;
                o.uv.xy = TRANSFORM_TEX(input.uv, _BaseMap);
                o.uv.zw = TRANSFORM_TEX(input.uv, _DetailNormalMap);
                o.normalWS = nrm.normalWS;
                o.tangentWS = half4(nrm.tangentWS, input.tangentOS.w * GetOddNegativeScale());
                return o;
            }

            //#region frag
            half4 frag(Varyings i) : SV_Target
            {
                half3 n1 = UnpackNormalScale(SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, i.uv.xy), _BumpScale);
                half3 n2 = UnpackNormalScale(SAMPLE_TEXTURE2D(_DetailNormalMap, sampler_DetailNormalMap, i.uv.zw), _DetailNormalScale);
                n1 = normalize(n1);
                n2 = normalize(n2);

                half3 blended;
                if (_BlendMode < 0.5)      blended = BlendNormalLinear(n1, n2);
                else if (_BlendMode < 1.5) blended = BlendNormalUDN(n1, n2);
                else if (_BlendMode < 2.5) blended = BlendNormalWhiteout(n1, n2);
                else if (_BlendMode < 3.5) blended = BlendNormalReoriented(n1, n2);
                else if (_BlendMode < 4.5) blended = n1;
                else                       blended = n2;
                // 遮罩：与 URP Lit 一样在“只有基础法线”和“混合结果”之间插值
                half3 normalTS = normalize(lerp(n1, blended, _DetailMask));

                float3 bitangent = i.tangentWS.w * cross(i.normalWS, i.tangentWS.xyz);
                half3 normalWS = NormalizeNormalPerPixel(
                    TransformTangentToWorld(normalTS, half3x3(i.tangentWS.xyz, bitangent, i.normalWS)));

                if (_ShowNormal > 0.5) return half4(normalTS * 0.5 + 0.5, 1);   // 直接看切线空间结果
                half3 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv.xy).rgb;
                return half4(Ch07Shade(i.positionWS, normalWS, albedo, 0.5, 0.2, 1), 1);
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
            #pragma vertex Ch07ShadowVert
            #pragma fragment Ch07NullFrag
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Assets/Cookbook/Ch07/Ch07Common.hlsl"
            ENDHLSL
        }
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            HLSLPROGRAM
            #pragma vertex Ch07DepthVert
            #pragma fragment Ch07NullFrag
            #include "Assets/Cookbook/Ch07/Ch07Common.hlsl"
            ENDHLSL
        }
    }
}
