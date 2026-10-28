// 案例 26.6：色差。沿径向把 R、G、B 采样到不同位置；采样数 > 3 时用“光谱权重”做平滑色散。
Shader "Cookbook/Ch26/MyChromaticAberration"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        ZTest Always ZWrite Off Cull Off
        Pass
        {
            Name "ChromaticAberration"
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float4 _CAParams;   // x 强度, y 采样数

            // t ∈ [0,1] 映射到 红→绿→蓝 的权重（三段帐篷函数），所有样本的权重之和按通道归一化
            half3 SpectrumWeight(float t)
            {
                half r = saturate(1.0 - abs(t * 2.0));
                half g = saturate(1.0 - abs(t * 2.0 - 1.0));
                half b = saturate(1.0 - abs(t * 2.0 - 2.0));
                return half3(r, g, b);
            }

            //#region frag
            half4 Frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                float2 uv = input.texcoord;
                float2 d = uv - 0.5;
                // 偏移随半径平方增长：中心几乎无色差，边缘最强（和真实镜头的横向色差一致）
                float2 offset = d * dot(d, d) * _CAParams.x * 0.15;

                int n = (int)_CAParams.y;
                half3 sum = 0, wsum = 0;
                [loop] for (int i = 0; i < n; i++)
                {
                    float t = i / (float)(n - 1);               // 0 = 红（向外）… 1 = 蓝（向内）
                    half3 w = SpectrumWeight(t);
                    float2 suv = uv + offset * (0.5 - t) * 2.0;
                    sum += SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, suv).rgb * w;
                    wsum += w;
                }
                return half4(sum / max(wsum, 1e-4), 1.0);
            }
            //#endregion
            ENDHLSL
        }
    }
}
