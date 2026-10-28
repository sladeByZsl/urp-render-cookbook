// 30.7 节：像素校验全屏 Pass——把 NaN / Inf / 负数 / 超范围的像素涂成醒目的颜色。
// 与 Rendering Debugger 里的 “Highlight NaN, Inf and Negative Values” 思路相同，但可以放进任何管线阶段。
Shader "Cookbook/Ch30/PixelValidator"
{
    Properties
    {
        _MaxValue ("Highlight Above", Float) = 64
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        ZWrite Off ZTest Always Cull Off Blend Off
        Pass
        {
            Name "Validate"
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float _MaxValue;
            CBUFFER_END

            //#region validate
            float4 Frag(Varyings input) : SV_Target
            {
                float4 c = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_PointClamp, input.texcoord);
                // 背景压暗、去色，让标记更显眼
                float3 bg = Luminance(saturate(c.rgb)) * 0.35;
                if (AnyIsNaN(c))              return float4(1, 0, 1, 1);   // 品红：NaN
                if (AnyIsInf(c))              return float4(0, 1, 1, 1);   // 青：Inf
                if (any(c.rgb < 0))           return float4(1, 1, 0, 1);   // 黄：负数
                if (any(c.rgb > _MaxValue))   return float4(1, 0.3, 0, 1); // 橙：异常大的 HDR 值
                return float4(bg, 1);
            }
            //#endregion
            ENDHLSL
        }
    }
}
