// 第 3 步：读取网格的顶点色，和贴图、颜色相乘。
Shader "Cookbook/Ch03/VertexColor"
{
    Properties
    {
        [MainTexture] _BaseMap ("Base Map", 2D) = "white" {}
        [MainColor]   _BaseColor ("Base Color", Color) = (1, 1, 1, 1)
        // 0 = 忽略顶点色，1 = 完全使用；做成滑条方便对比
        _VertexColorStrength ("Vertex Color Strength", Range(0, 1)) = 1
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        Pass
        {
            Name "Unlit"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            //#region io
            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv         : TEXCOORD0;
                half4  color      : COLOR;      // 顶点色：Mesh.colors，没有顶点色的网格读到 (1,1,1,1)
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
                half4  color      : COLOR;      // 光栅化时在三角形内部线性插值
            };
            //#endregion

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);
            float4 _BaseMap_ST;
            half4  _BaseColor;
            half   _VertexColorStrength;

            //#region vertfrag
            Varyings vert (Attributes input)
            {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                output.color = input.color;     // 原样传下去，插值交给硬件
                return output;
            }

            half4 frag (Varyings input) : SV_Target
            {
                half4 tex = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv);
                // lerp(1, 顶点色, 强度)：强度为 0 时乘以白色，等于不起作用
                half4 vc = lerp(half4(1, 1, 1, 1), input.color, _VertexColorStrength);
                return tex * _BaseColor * vc;
            }
            //#endregion
            ENDHLSL
        }
    }
}
