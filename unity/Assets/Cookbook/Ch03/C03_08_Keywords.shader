// 第 8 步：用关键字（Keyword）做功能开关 —— 一份源码，按需编译出多个变体。
// 这是本章的“完成版”：纹理、顶点色、Alpha Clip、雾、SRP Batcher、阴影、深度全部具备。
Shader "Cookbook/Ch03/Keywords"
{
    Properties
    {
        [MainTexture] _BaseMap ("Base Map", 2D) = "white" {}
        [MainColor]   _BaseColor ("Base Color", Color) = (1, 1, 1, 1)

        //#region props
        // [Toggle(关键字)]：勾选时启用该关键字，属性值同时变成 1
        [Toggle(_VERTEX_COLOR_ON)] _UseVertexColor ("Use Vertex Color", Float) = 0
        [Toggle(_ALPHATEST_ON)]    _AlphaClip ("Alpha Clip", Float) = 0
        _Cutoff ("Alpha Cutoff", Range(0, 1)) = 0.5
        // [KeywordEnum(A, B)]：生成关键字 _属性名大写_选项大写，即 _UVSOURCE_MESH / _UVSOURCE_WORLDXZ
        [KeywordEnum(Mesh, WorldXZ)] _UVSource ("UV Source", Float) = 0
        _WorldUVScale ("World UV Scale", Float) = 0.5
        [Enum(UnityEngine.Rendering.CullMode)] _Cull ("Cull", Float) = 2
        //#endregion
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half4  _BaseColor;
            half   _Cutoff;
            float  _WorldUVScale;
        CBUFFER_END

        TEXTURE2D(_BaseMap);
        SAMPLER(sampler_BaseMap);

        //#region uv
        // 根据关键字选择 UV 来源。#if 在编译期决定，没被选中的分支根本不会进入这个变体
        float2 ComputeUV(float2 meshUV, float3 positionWS)
        {
        #if defined(_UVSOURCE_WORLDXZ)
            float2 uv = positionWS.xz * _WorldUVScale;   // 俯视投影：相邻物体的纹理无缝衔接
        #else
            float2 uv = meshUV;
        #endif
            return TRANSFORM_TEX(uv, _BaseMap);
        }

        void ClipByAlpha(float2 uv)
        {
        #if defined(_ALPHATEST_ON)
            half a = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uv).a * _BaseColor.a;
            clip(a - _Cutoff);
        #endif
        }
        //#endregion
        ENDHLSL

        Pass
        {
            Name "Unlit"
            // 不需要 GBuffer 的 Unlit：用 UniversalForwardOnly，Forward / Forward+ / Deferred 三种路径都会画它
            Tags { "LightMode"="UniversalForwardOnly" }
            Cull [_Cull]

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            //#region pragmas
            // 材质开关：shader_feature —— 只编译“有材质用到”的组合；_local 不占用全局关键字名额
            #pragma shader_feature_local _VERTEX_COLOR_ON
            #pragma shader_feature_local_fragment _ALPHATEST_ON
            #pragma shader_feature_local _UVSOURCE_MESH _UVSOURCE_WORLDXZ
            // 全局开关：multi_compile —— 运行时可能切换，所有组合都要编译进包
            #pragma multi_compile_fog
            //#endregion

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv         : TEXCOORD0;
            #if defined(_VERTEX_COLOR_ON)
                half4  color      : COLOR;
            #endif
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
                float  fogFactor  : TEXCOORD1;
            #if defined(_VERTEX_COLOR_ON)
                half4  color      : COLOR;      // 不用顶点色的变体连插值器都省掉
            #endif
            };

            Varyings vert (Attributes input)
            {
                Varyings output;
                VertexPositionInputs pos = GetVertexPositionInputs(input.positionOS.xyz);
                output.positionCS = pos.positionCS;
                output.uv = ComputeUV(input.uv, pos.positionWS);
                output.fogFactor = ComputeFogFactor(pos.positionCS.z);
            #if defined(_VERTEX_COLOR_ON)
                output.color = input.color;
            #endif
                return output;
            }

            //#region frag
            half4 frag (Varyings input) : SV_Target
            {
                half4 tex = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv);
            #if defined(_ALPHATEST_ON)
                clip(tex.a * _BaseColor.a - _Cutoff);
            #endif
                half3 rgb = tex.rgb * _BaseColor.rgb;
            #if defined(_VERTEX_COLOR_ON)
                rgb *= input.color.rgb;
            #endif
                rgb = MixFog(rgb, input.fogFactor);
                return half4(rgb, 1);
            }
            //#endregion
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull [_Cull]

            HLSLPROGRAM
            #pragma vertex ShadowVert
            #pragma fragment ShadowFrag
            #pragma shader_feature_local _ALPHATEST_ON
            #pragma shader_feature_local _UVSOURCE_MESH _UVSOURCE_WORLDXZ
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            // Shadows.hlsl 用到了 CommonMaterial.hlsl 里的 LerpWhiteTo，单独引用时要先包含它
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            float3 _LightDirection;
            float3 _LightPosition;

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; float2 uv : TEXCOORD0; };
            struct Varyings   { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; };

            Varyings ShadowVert (Attributes input)
            {
                Varyings output;
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 normalWS   = TransformObjectToWorldNormal(input.normalOS);
            #if defined(_CASTING_PUNCTUAL_LIGHT_SHADOW)
                float3 lightDirectionWS = normalize(_LightPosition - positionWS);
            #else
                float3 lightDirectionWS = _LightDirection;
            #endif
                output.positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS));
            #if UNITY_REVERSED_Z
                output.positionCS.z = min(output.positionCS.z, UNITY_NEAR_CLIP_VALUE);
            #else
                output.positionCS.z = max(output.positionCS.z, UNITY_NEAR_CLIP_VALUE);
            #endif
                output.uv = ComputeUV(input.uv, positionWS);
                return output;
            }

            half4 ShadowFrag (Varyings input) : SV_Target
            {
                ClipByAlpha(input.uv);
                return 0;
            }
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On
            ColorMask R
            Cull [_Cull]

            HLSLPROGRAM
            #pragma vertex DepthVert
            #pragma fragment DepthFrag
            #pragma shader_feature_local _ALPHATEST_ON
            #pragma shader_feature_local _UVSOURCE_MESH _UVSOURCE_WORLDXZ

            struct Attributes { float4 positionOS : POSITION; float2 uv : TEXCOORD0; };
            struct Varyings   { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; };

            Varyings DepthVert (Attributes input)
            {
                Varyings output;
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                output.positionCS = TransformWorldToHClip(positionWS);
                output.uv = ComputeUV(input.uv, positionWS);
                return output;
            }

            half DepthFrag (Varyings input) : SV_Target
            {
                ClipByAlpha(input.uv);
                return input.positionCS.z;
            }
            ENDHLSL
        }
    }
}
