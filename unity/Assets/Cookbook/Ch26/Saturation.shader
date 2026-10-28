// 案例 26.1：饱和度 / 对比度。
Shader "Cookbook/Ch26/Saturation"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        ZTest Always ZWrite Off Cull Off

        Pass
        {
            Name "Saturation"
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float _Saturation;
            float _Contrast;

            //#region frag
            half4 Frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                half4 color = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, input.texcoord);

                // 饱和度：在“原色”与“同亮度的灰”之间插值，>1 时外插 = 更鲜艳
                half luma = dot(color.rgb, half3(0.2126, 0.7152, 0.0722));
                color.rgb = lerp(luma.xxx, color.rgb, _Saturation);

                // 对比度：在 log2 空间以中灰为支点缩放，HDR 亮部不会被直接截断
                const half midGrey = 0.18;
                half3 logC = log2(max(color.rgb, 1e-5) / midGrey);
                color.rgb = midGrey * exp2(logC * _Contrast);
                return color;
            }
            //#endregion
            ENDHLSL
        }
    }
}
