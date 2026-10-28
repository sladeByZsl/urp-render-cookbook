// 标准的切线空间法线贴图：顶点里准备 TBN，片元里解码法线贴图并变换到世界空间。
Shader "Cookbook/Ch07/NormalMap"
{
    Properties
    {
        [MainTexture] _BaseMap("Albedo", 2D) = "white" {}
        [MainColor] _BaseColor("Color", Color) = (1, 1, 1, 1)
        [Toggle(_NORMALMAP)] _UseNormalMap("Use Normal Map", Float) = 1
        [NoScaleOffset][Normal] _BumpMap("Normal Map", 2D) = "bump" {}
        _BumpScale("Normal Scale", Range(0, 3)) = 1
        _Gloss("Gloss", Range(0, 1)) = 0.45
        _SpecStrength("Specular", Range(0, 1)) = 0.15
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half4 _BaseColor;
            half _BumpScale;
            half _Gloss;
            half _SpecStrength;
        CBUFFER_END
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma shader_feature_local _NORMALMAP
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #pragma multi_compile_fog
            #include "Assets/Cookbook/Ch07/Ch07Common.hlsl"

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);
            TEXTURE2D(_BumpMap); SAMPLER(sampler_BumpMap);

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float4 tangentOS  : TANGENT;
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS   : TEXCOORD2;
            #if defined(_NORMALMAP)
                half4  tangentWS  : TEXCOORD3;   // xyz 切线，w 副切线符号
            #endif
                half   fogFactor  : TEXCOORD4;
            };

            //#region vert
            Varyings vert(Attributes input)
            {
                Varyings o;
                VertexPositionInputs pos = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs nrm = GetVertexNormalInputs(input.normalOS, input.tangentOS);
                o.positionCS = pos.positionCS;
                o.positionWS = pos.positionWS;
                o.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                o.normalWS = nrm.normalWS;
            #if defined(_NORMALMAP)
                // 与 URP Lit 相同：只传 T 和符号，B 在片元里用叉乘重建，省一个插值器
                real sign = input.tangentOS.w * GetOddNegativeScale();
                o.tangentWS = half4(nrm.tangentWS, sign);
            #endif
                o.fogFactor = ComputeFogFactor(pos.positionCS.z);
                return o;
            }
            //#endregion

            //#region frag
            half4 frag(Varyings i) : SV_Target
            {
                half4 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv) * _BaseColor;

            #if defined(_NORMALMAP)
                // 1) 解码：自动处理 DXT5nm/BC5（AG/RG 两通道）与 RGB 三通道两种存储
                half3 normalTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, i.uv), _BumpScale);
                // 2) 重建副切线并组装 TBN（行向量 T、B、N）
                float sgn = i.tangentWS.w;
                float3 bitangent = sgn * cross(i.normalWS, i.tangentWS.xyz);
                half3x3 tangentToWorld = half3x3(i.tangentWS.xyz, bitangent, i.normalWS);
                // 3) 切线空间 → 世界空间
                half3 normalWS = TransformTangentToWorld(normalTS, tangentToWorld);
            #else
                half3 normalWS = i.normalWS;
            #endif
                normalWS = NormalizeNormalPerPixel(normalWS);

                half3 color = Ch07Shade(i.positionWS, normalWS, albedo.rgb, _Gloss, _SpecStrength, 1);
                color = MixFog(color, i.fogFactor);
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
