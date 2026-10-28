// 案例 20.5：线性混合 vs 高度混合——砖地上长出的草先填满砖缝
Shader "Cookbook/Ch20/HeightBlend"
{
    Properties
    {
        _MapA ("Layer A Albedo", 2D) = "white" {}
        [NoScaleOffset] _HeightA ("Layer A Height (R)", 2D) = "gray" {}
        [NoScaleOffset][Normal] _NormalA ("Layer A Normal", 2D) = "bump" {}
        [NoScaleOffset] _MapB ("Layer B Albedo (A=Height)", 2D) = "white" {}
        _TilingB ("Layer B Tiling", Float) = 2
        [NoScaleOffset] _NoiseTex ("Mask Noise", 2D) = "gray" {}
        _MaskContrast ("Mask Contrast", Float) = 2.5
        _MaskOffset ("Mask Offset", Range(-1, 1)) = 0
        _UseHeight ("Use Height Blend", Range(0, 1)) = 1
        _BlendDepth ("Blend Depth", Range(0.01, 1)) = 0.1
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        CBUFFER_START(UnityPerMaterial)
            float4 _MapA_ST;
            float _TilingB;
            half _MaskContrast, _MaskOffset, _UseHeight, _BlendDepth;
        CBUFFER_END
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }   // 自定义表面混合，没有 GBuffer Pass：Deferred 下也走前向
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #pragma multi_compile _ _FORWARD_PLUS
            #pragma multi_compile_fog
            #pragma multi_compile_instancing

            #include "Assets/Cookbook/Ch20/TerrainCommon.hlsl"

            TEXTURE2D(_MapA);    SAMPLER(sampler_MapA);
            TEXTURE2D(_HeightA);
            TEXTURE2D(_NormalA);
            TEXTURE2D(_MapB);
            TEXTURE2D(_NoiseTex); SAMPLER(sampler_NoiseTex);

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float4 tangentOS  : TANGENT;
                float2 uv         : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                half3  normalWS   : TEXCOORD1;
                half4  tangentWS  : TEXCOORD2;
                float2 uv         : TEXCOORD3;
                half   fogFactor  : TEXCOORD4;
            };

            Varyings vert(Attributes v)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                VertexPositionInputs p = GetVertexPositionInputs(v.positionOS.xyz);
                VertexNormalInputs nI = GetVertexNormalInputs(v.normalOS, v.tangentOS);
                o.positionCS = p.positionCS;
                o.positionWS = p.positionWS;
                o.normalWS = nI.normalWS;
                o.tangentWS = half4(nI.tangentWS, v.tangentOS.w * GetOddNegativeScale());
                o.uv = v.uv;
                o.fogFactor = ComputeFogFactor(p.positionCS.z);
                return o;
            }

            //#region frag
            half4 frag(Varyings i) : SV_Target
            {
                float2 uvA = TRANSFORM_TEX(i.uv, _MapA);
                float2 uvB = i.uv * _TilingB;
                half3 albedoA = SAMPLE_TEXTURE2D(_MapA, sampler_MapA, uvA).rgb;
                half  heightA = SAMPLE_TEXTURE2D(_HeightA, sampler_MapA, uvA).r;
                half3 normalA = UnpackNormal(SAMPLE_TEXTURE2D(_NormalA, sampler_MapA, uvA));
                half4 layerB  = SAMPLE_TEXTURE2D(_MapB, sampler_MapA, uvB);

                // 遮罩：从左到右的渐变 + 噪声，模拟“刷”出来的过渡区
                half noise = SAMPLE_TEXTURE2D(_NoiseTex, sampler_NoiseTex, i.uv * 1.5).r - 0.5;
                half mask = saturate((i.uv.x - 0.5 + _MaskOffset + noise * 0.35) * _MaskContrast + 0.5);

                // 线性混合 vs 高度混合
                half tLinear = mask;
                half tHeight = HeightBlendWeight(heightA, layerB.a, mask, _BlendDepth);
                half t = lerp(tLinear, tHeight, _UseHeight);

                half3 albedo = lerp(albedoA, layerB.rgb, t);
                half3 normalTS = normalize(lerp(normalA, half3(0, 0, 1), t));
                float sgn = i.tangentWS.w;
                float3 bitangent = sgn * cross(i.normalWS, i.tangentWS.xyz);
                half3 normalWS = TransformTangentToWorld(normalTS, half3x3(i.tangentWS.xyz, bitangent, i.normalWS));
                half occlusion = lerp(lerp(0.6, 1.0, heightA), 1.0, t);   // 砖缝顺手压暗一点
                return Ch20ShadePBR(i.positionWS, normalWS, i.positionCS, albedo, 0, lerp(0.3, 0.12, t), occlusion, i.fogFactor);
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
            #pragma vertex Ch20ShadowVert
            #pragma fragment Ch20EmptyFrag
            #pragma multi_compile_instancing
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Assets/Cookbook/Ch20/ShadowDepthPasses.hlsl"
            ENDHLSL
        }
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            HLSLPROGRAM
            #pragma vertex Ch20DepthVert
            #pragma fragment Ch20EmptyFrag
            #pragma multi_compile_instancing
            #include "Assets/Cookbook/Ch20/ShadowDepthPasses.hlsl"
            ENDHLSL
        }
    }
}
