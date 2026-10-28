// 第 2 章 2.10 节 / 案例 2.6：兼容 SRP Batcher 的最小 Shader
// 关键：所有材质属性（Properties 里声明的）都放进同一个名为 UnityPerMaterial 的 CBUFFER，
// 并且每个 Pass 里这个 CBUFFER 的内容和顺序完全一致。
Shader "Cookbook/Ch02/SrpBatcherCompatible"
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

            //#region cbuffer
            // 纹理对象本身不进 CBUFFER，但它的 _ST（缩放平移）是数值，要进
            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);
            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                half4  _BaseColor;
            CBUFFER_END
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
