// 法线贴图的三种常见“写错/用错”，与正确写法放在一起对比。
Shader "Cookbook/Ch07/NormalMistakes"
{
    Properties
    {
        [MainTexture] _BaseMap("Albedo", 2D) = "white" {}
        [NoScaleOffset][Normal] _BumpMap("Normal Map", 2D) = "bump" {}
        _BumpScale("Normal Scale", Range(0, 3)) = 1
        [Enum(Correct,0,RawRGB,1,FlipY,2,SkipNormalize,3)] _Mistake("Mistake", Float) = 0
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half _BumpScale;
            half _Mistake;
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

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);
            TEXTURE2D(_BumpMap); SAMPLER(sampler_BumpMap);

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; float4 tangentOS : TANGENT; float2 uv : TEXCOORD0; };
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
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
                o.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                o.normalWS = nrm.normalWS;
                o.tangentWS = half4(nrm.tangentWS, input.tangentOS.w * GetOddNegativeScale());
                return o;
            }

            //#region frag
            half4 frag(Varyings i) : SV_Target
            {
                half4 packed = SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, i.uv);
                half3 normalTS;
                if (_Mistake > 0.5 && _Mistake < 1.5)
                {
                    // 错误 1：照搬“rgb*2-1”。桌面平台法线贴图默认压成 DXT5nm/BC5，
                    // 数据在 A/G（或 R/G）通道里，B 通道是 0，这样解出来的向量完全不对
                    normalTS = packed.rgb * 2.0 - 1.0;
                    normalTS.xy *= _BumpScale;
                }
                else
                {
                    normalTS = UnpackNormalScale(packed, _BumpScale);
                    // 错误 2：贴图按 DirectX 约定（Y 朝下）烘焙，却直接给 Unity（OpenGL 约定，Y 朝上）用
                    if (_Mistake > 1.5 && _Mistake < 2.5) normalTS.y = -normalTS.y;
                }

                float3 bitangent = i.tangentWS.w * cross(i.normalWS, i.tangentWS.xyz);
                half3 normalWS = TransformTangentToWorld(normalTS, half3x3(i.tangentWS.xyz, bitangent, i.normalWS));
                // 错误 3：忘了归一化（插值后的 TBN 和缩放过的 normalTS 都不是单位长度）
                if (_Mistake < 2.5) normalWS = normalize(normalWS);

                half3 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv).rgb;
                return half4(Ch07Shade(i.positionWS, normalWS, albedo, 0.45, 0.15, 1), 1);
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
