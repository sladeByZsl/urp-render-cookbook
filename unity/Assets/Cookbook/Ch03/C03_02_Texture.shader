// 第 2 步：采样一张贴图，支持材质面板上的 Tiling / Offset。
Shader "Cookbook/Ch03/Textured"
{
    Properties
    {
        //#region props
        [MainTexture] _BaseMap ("Base Map", 2D) = "white" {}
        [MainColor]   _BaseColor ("Base Color", Color) = (1, 1, 1, 1)
        //#endregion
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

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv         : TEXCOORD0;  // 第 0 套 UV
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;  // 插值器：TEXCOORDn 只是“通用槽位”的名字
            };

            //#region decl
            // 纹理对象和采样器分开声明（DX11 风格），宏会替各平台展开成正确的写法
            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);    // 命名为 sampler + 纹理名，Unity 会自动使用该纹理的过滤/寻址设置

            float4 _BaseMap_ST;          // Unity 自动填充：xy = Tiling，zw = Offset
            half4  _BaseColor;
            //#endregion

            //#region vertfrag
            Varyings vert (Attributes input)
            {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                // 等价于 input.uv * _BaseMap_ST.xy + _BaseMap_ST.zw
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                return output;
            }

            half4 frag (Varyings input) : SV_Target
            {
                half4 tex = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv);
                return tex * _BaseColor;
            }
            //#endregion
            ENDHLSL
        }
    }
}
