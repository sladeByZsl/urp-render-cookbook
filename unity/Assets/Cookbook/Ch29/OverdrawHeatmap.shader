// 案例 29.5：把 Overdraw 计数映射成热度图（全屏 Pass，源纹理是计数 RT）。
// 色阶：0 黑 → 1 深蓝 → 2 青 → 3 绿 → 4 黄 → 6 橙 → 8 红 → 12+ 白
Shader "Cookbook/Ch29/OverdrawHeatmap"
{
    Properties
    {
        _MaxCount ("Count For White", Float) = 12
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        ZWrite Off ZTest Always Cull Off Blend Off
        Pass
        {
            Name "Heatmap"
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float _MaxCount;
            CBUFFER_END

            //#region ramp
            half3 HeatRamp(float n)
            {
                static const float3 c[8] = {
                    float3(0, 0, 0), float3(0.05, 0.1, 0.55), float3(0.0, 0.6, 0.8), float3(0.1, 0.75, 0.2),
                    float3(0.95, 0.9, 0.1), float3(1.0, 0.5, 0.05), float3(0.9, 0.08, 0.05), float3(1, 1, 1) };
                static const float k[8] = { 0, 1, 2, 3, 4, 6, 8, 12 };
                n = min(n, k[7] * _MaxCount / 12);
                float3 col = c[7];
                for (int i = 0; i < 7; i++)
                {
                    float a = k[i] * _MaxCount / 12, b = k[i + 1] * _MaxCount / 12;
                    if (n >= a && n < b) { col = lerp(c[i], c[i + 1], (n - a) / (b - a)); break; }
                }
                return col;
            }
            //#endregion

            half4 Frag(Varyings input) : SV_Target
            {
                float count = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_PointClamp, input.texcoord).r;
                return half4(HeatRamp(count), 1);
            }
            ENDHLSL
        }
    }
}
