// 网格没有切线数据时，用屏幕导数在像素里现算切线框架（per-pixel tangent frame）。
Shader "Cookbook/Ch07/DerivativeTBN"
{
    Properties
    {
        [MainTexture] _BaseMap("Albedo", 2D) = "white" {}
        [MainColor] _BaseColor("Color", Color) = (1, 1, 1, 1)
        [NoScaleOffset][Normal] _BumpMap("Normal Map", 2D) = "bump" {}
        _BumpScale("Normal Scale", Range(0, 3)) = 1
        [Toggle(_DERIVATIVE_TBN)] _UseDerivative("Derivative TBN", Float) = 1
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
        CBUFFER_END
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma shader_feature_local _DERIVATIVE_TBN
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

            //#region frame
            // 由 dp = T·du + B·dv 在屏幕 x、y 两个方向各写一次，解出 T = ∂p/∂u、B = ∂p/∂v。
            // 乘 sign(det) 保证结果与屏幕 y 轴朝向（平台差异）无关，并自动处理镜像 UV。
            half3x3 DerivativeTangentFrame(float3 N, float3 positionWS, float2 uv)
            {
                float3 dp1 = ddx(positionWS), dp2 = ddy(positionWS);
                float2 duv1 = ddx(uv),        duv2 = ddy(uv);
                float det = duv1.x * duv2.y - duv1.y * duv2.x;
                float s = det < 0 ? -1.0 : 1.0;
                float3 T = (dp1 * duv2.y - dp2 * duv1.y) * s;
                float3 B = (dp2 * duv1.x - dp1 * duv2.x) * s;
                // Gram-Schmidt：去掉与插值法线平行的分量，避免三角形之间出现折痕
                T = normalize(T - N * dot(N, T));
                B = normalize(B - N * dot(N, B));
                return half3x3(T, B, N);
            }
            //#endregion

            half4 frag(Varyings i) : SV_Target
            {
                float3 N = normalize(i.normalWS);
                half3 normalTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, i.uv), _BumpScale);
            #if defined(_DERIVATIVE_TBN)
                half3x3 tbn = DerivativeTangentFrame(N, i.positionWS, i.uv);
            #else
                float3 bitangent = i.tangentWS.w * cross(i.normalWS, i.tangentWS.xyz);
                half3x3 tbn = half3x3(i.tangentWS.xyz, bitangent, i.normalWS);
            #endif
                half3 normalWS = NormalizeNormalPerPixel(TransformTangentToWorld(normalTS, tbn));
                half3 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv).rgb * _BaseColor.rgb;
                return half4(Ch07Shade(i.positionWS, normalWS, albedo, 0.45, 0.15, 1), 1);
            }
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
