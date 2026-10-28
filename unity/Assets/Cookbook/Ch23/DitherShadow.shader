// 案例 23.8：半透明物体的抖动阴影（Dithered Shadow）。
// 阴影贴图只存一个深度，表达不了“半透明”。办法是在 ShadowCaster 里按透明度用 Bayer 矩阵
// 有规律地丢掉一部分像素：alpha = 0.3 就大约只留 30% 的阴影像素，再经过软阴影 PCF 一平均，
// 接收端看到的就是“30% 浓度”的阴影。
Shader "Cookbook/Ch23/DitherShadow"
{
    Properties
    {
        [MainTexture] _BaseMap ("Base Map (A = 透明度)", 2D) = "white" {}
        [MainColor]   _BaseColor ("Base Color", Color) = (0.3, 0.7, 1, 0.4)
        [Toggle] _DitherShadow ("Dither Shadow", Float) = 1
        _ShadowAlphaScale ("Shadow Alpha Scale", Range(0, 2)) = 1
    }
    SubShader
    {
        Tags { "RenderType"="Transparent" "RenderPipeline"="UniversalPipeline" "Queue"="Transparent" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half4  _BaseColor;
            half   _DitherShadow;
            half   _ShadowAlphaScale;
        CBUFFER_END
        TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            Cull Back

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; float2 uv : TEXCOORD0; };
            struct Varyings { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; half3 normalWS : TEXCOORD1; float3 positionWS : TEXCOORD2; };
            Varyings vert(Attributes v)
            {
                Varyings o;
                VertexPositionInputs p = GetVertexPositionInputs(v.positionOS.xyz);
                o.positionCS = p.positionCS; o.positionWS = p.positionWS;
                o.normalWS = TransformObjectToWorldNormal(v.normalOS);
                o.uv = TRANSFORM_TEX(v.uv, _BaseMap);
                return o;
            }
            half4 frag(Varyings i) : SV_Target
            {
                half4 tex = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv) * _BaseColor;
                half3 n = normalize(i.normalWS);
                Light l = GetMainLight();
                half3 v = GetWorldSpaceNormalizeViewDir(i.positionWS);
                half3 h = normalize(l.direction + v);
                half spec = pow(saturate(dot(n, h)), 64) * 0.6;
                half3 c = tex.rgb * (l.color * saturate(dot(n, l.direction)) + SampleSH(n)) + spec * l.color;
                return half4(c, tex.a);
            }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0
            Cull Back

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Assets/Cookbook/Ch23/Ch23Common.hlsl"

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; float2 uv : TEXCOORD0; };
            struct Varyings { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; };

            Varyings vert(Attributes v)
            {
                Varyings o;
                CasterAttributes c;
                c.positionOS = v.positionOS;
                c.normalOS = v.normalOS;
                o.positionCS = Ch23ShadowCasterVert(c);
                o.uv = TRANSFORM_TEX(v.uv, _BaseMap);
                return o;
            }

            //#region dither
            // 4×4 Bayer 矩阵：相邻阈值尽量分散，丢弃的像素在空间上均匀
            static const half kBayer4x4[16] =
            {
                 0,  8,  2, 10,
                12,  4, 14,  6,
                 3, 11,  1,  9,
                15,  7, 13,  5
            };

            half4 frag(Varyings i) : SV_Target
            {
                half alpha = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv).a * _BaseColor.a * _ShadowAlphaScale;
                if (_DitherShadow > 0.5)
                {
                    // 在 ShadowCaster 里，SV_POSITION.xy 就是阴影贴图上的像素坐标
                    uint2 p = uint2(i.positionCS.xy) & 3;
                    half threshold = (kBayer4x4[p.y * 4 + p.x] + 0.5) / 16.0;
                    clip(alpha - threshold);
                }
                return 0;
            }
            //#endregion
            ENDHLSL
        }
    }
}
