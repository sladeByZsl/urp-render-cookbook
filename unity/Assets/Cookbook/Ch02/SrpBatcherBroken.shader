// 第 2 章 2.10 节 / 案例 2.6：一个“看起来没问题”、却不兼容 SRP Batcher 的 Shader
// 问题：_BaseColor 是材质属性，却声明在 CBUFFER 之外。Inspector 里会显示
// “SRP Batcher: not compatible”，原因是 “Material property is found in another cbuffer than UnityPerMaterial”。
Shader "Cookbook/Ch02/SrpBatcherBroken"
{
    Properties
    {
        _BaseColor ("颜色", Color) = (1, 1, 1, 1)
        _BaseMap ("贴图", 2D) = "white" {}
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }
        Pass
        {
            Tags { "LightMode"="UniversalForward" }
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            //#region broken
            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);
            float4 _BaseMap_ST;     // ✗ 不在 UnityPerMaterial 里
            half4  _BaseColor;      // ✗ 不在 UnityPerMaterial 里
            //#endregion

            struct Attributes { float4 positionOS : POSITION; float2 uv : TEXCOORD0; };
            struct Varyings   { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; };

            Varyings vert(Attributes input)
            {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                return output;
            }
            half4 frag(Varyings input) : SV_Target
            {
                return SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv) * _BaseColor;
            }
            ENDHLSL
        }
    }
}
