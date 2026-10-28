// 案例 20.6：四层 Splatmap 混合（仿 URP TerrainLit 的数据布局：_Control 的 RGBA 是四层权重）
Shader "Cookbook/Ch20/Splatmap"
{
    Properties
    {
        [NoScaleOffset] _Control ("Control (RGBA = 4 layer weights)", 2D) = "red" {}
        [NoScaleOffset] _Splat0 ("Layer 0 (A=Height)", 2D) = "white" {}
        [NoScaleOffset] _Splat1 ("Layer 1 (A=Height)", 2D) = "white" {}
        [NoScaleOffset] _Splat2 ("Layer 2 (A=Height)", 2D) = "white" {}
        [NoScaleOffset] _Splat3 ("Layer 3 (A=Height)", 2D) = "white" {}
        [NoScaleOffset][Normal] _Normal2 ("Layer 2 Normal", 2D) = "bump" {}
        _SplatTiling ("Layer Tiling (1/m)", Vector) = (0.35, 0.45, 0.2, 0.18)
        _HeightTransition ("Height Transition", Range(0, 1)) = 0.2
        [Toggle] _HeightBased ("Height Based Blend", Float) = 1
        [Toggle(_DEBUG_CONTROL)] _DebugControl ("Show Control Map", Float) = 0
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        CBUFFER_START(UnityPerMaterial)
            float4 _SplatTiling;
            half _HeightTransition;
            half _HeightBased;
        CBUFFER_END
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }   // 自定义表面混合，没有 GBuffer Pass：Deferred 下也走前向
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma shader_feature_local_fragment _DEBUG_CONTROL
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #pragma multi_compile _ _FORWARD_PLUS
            #pragma multi_compile_fog
            #pragma multi_compile_instancing

            #include "Assets/Cookbook/Ch20/TerrainCommon.hlsl"

            TEXTURE2D(_Control); SAMPLER(sampler_Control);
            TEXTURE2D(_Splat0);  SAMPLER(sampler_Splat0);   // 与 TerrainLit 一样，四层共用 sampler_Splat0
            TEXTURE2D(_Splat1);
            TEXTURE2D(_Splat2);
            TEXTURE2D(_Splat3);
            TEXTURE2D(_Normal2);

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                half3  normalWS   : TEXCOORD1;
                float2 uv         : TEXCOORD2;
                half   fogFactor  : TEXCOORD3;
            };

            Varyings vert(Attributes v)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                VertexPositionInputs p = GetVertexPositionInputs(v.positionOS.xyz);
                o.positionCS = p.positionCS;
                o.positionWS = p.positionWS;
                o.normalWS = TransformObjectToWorldNormal(v.normalOS);
                o.uv = v.uv;
                o.fogFactor = ComputeFogFactor(p.positionCS.z);
                return o;
            }

            //#region heightSplat
            // 与 TerrainLit 的 HeightBasedSplatModify 同一思路：
            // 高度 × 权重，取最高者，比它低 transition 以上的层直接归零，剩下的重新归一化
            half4 HeightBasedSplat(half4 control, half4 heights, half transition)
            {
                half4 h = heights * control;
                half maxH = max(max(h.r, h.g), max(h.b, h.a));
                half4 w = max(h + max(transition, 1e-5) - maxH, 0);
                w = (w + 1e-6) * control;                  // 权重为 0 的层永远不出现
                return w / max(dot(w, 1.0), 1e-6);
            }
            //#endregion

            //#region frag
            half4 frag(Varyings i) : SV_Target
            {
                half3 n = normalize(i.normalWS);
                half4 control = SAMPLE_TEXTURE2D(_Control, sampler_Control, i.uv);
                control /= max(dot(control, 1.0), 1e-4);   // 画笔刷出来的权重不一定和为 1

            #if defined(_DEBUG_CONTROL)
                half3 dbg = control.r * half3(0.2, 0.7, 0.15) + control.g * half3(0.85, 0.6, 0.25)
                          + control.b * half3(0.6, 0.6, 0.65) + control.a * half3(1, 1, 1);
                return half4(dbg * (0.55 + 0.45 * saturate(dot(n, half3(0.3, 0.9, -0.3)))), 1);
            #endif

                float2 xz = i.positionWS.xz;
                half4 s0 = SAMPLE_TEXTURE2D(_Splat0, sampler_Splat0, xz * _SplatTiling.x);
                half4 s1 = SAMPLE_TEXTURE2D(_Splat1, sampler_Splat0, xz * _SplatTiling.y);
                half4 s3 = SAMPLE_TEXTURE2D(_Splat3, sampler_Splat0, xz * _SplatTiling.w);
                // 第 2 层是岩石，崖壁上用 Triplanar（TerrainLit 本身没有这一步）
                float3 tw = TriplanarWeights(n, 8);
                TriplanarUV tuv = GetTriplanarUV(i.positionWS, n, _SplatTiling.z);
                half4 s2 = SampleTriplanar(TEXTURE2D_ARGS(_Splat2, sampler_Splat0), tuv, tw);
                half3 rockN = TriplanarNormalWS(TEXTURE2D_ARGS(_Normal2, sampler_Splat0), tuv, tw, n, 1, 3);

                if (_HeightBased > 0.5)
                    control = HeightBasedSplat(control, half4(s0.a, s1.a, s2.a, s3.a), _HeightTransition);

                half3 albedo = s0.rgb * control.r + s1.rgb * control.g + s2.rgb * control.b + s3.rgb * control.a;
                half3 normalWS = normalize(lerp(n, rockN, control.b));
                half smoothness = dot(control, half4(0.1, 0.15, 0.25, 0.5));
                return Ch20ShadePBR(i.positionWS, normalWS, i.positionCS, albedo, 0, smoothness, 1, i.fogFactor);
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
        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode"="DepthNormals" }
            ZWrite On
            HLSLPROGRAM
            #pragma vertex Ch20DepthVert
            #pragma fragment Ch20DepthNormalsFrag
            #pragma multi_compile_instancing
            #include "Assets/Cookbook/Ch20/ShadowDepthPasses.hlsl"
            ENDHLSL
        }
    }
}
