// 30.7 节问题现场二（错误示范）：线性空间项目里，自定义后处理又手动做了一次 Gamma 校正。
// URP 在线性空间下最终写入 sRGB 目标时会自动编码，这一次 pow(1/2.2) 是多余的，画面整体发灰发白。
Shader "Cookbook/Ch30/ManualGamma"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        ZWrite Off ZTest Always Cull Off Blend Off
        Pass
        {
            Name "ManualGamma"
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            //#region bug
            half4 Frag(Varyings input) : SV_Target
            {
                half4 c = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_PointClamp, input.texcoord);
                c.rgb = pow(max(c.rgb, 0), 1.0 / 2.2);   // ✗ 多余：线性 → sRGB 的编码交给管线
                return c;
            }
            //#endregion
            ENDHLSL
        }
    }
}
