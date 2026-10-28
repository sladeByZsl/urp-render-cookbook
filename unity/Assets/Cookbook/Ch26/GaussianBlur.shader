// 案例 26.2：可分离高斯。9 个权重的一维高斯核，借助双线性过滤只需 5 次采样。
Shader "Cookbook/Ch26/GaussianBlur"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        ZTest Always ZWrite Off Cull Off

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

        float4 _BlitTexture_TexelSize;
        float  _Spread;

        //#region blur
        // 9 抽头核 [66 220 495 792 924 792 495 220 66]/4070（二项式第 12 行去掉最外两对后归一化，
        // 与 URP Bloom.shader 用的是同一组权重）。相邻两项合并成一次双线性采样：
        // 偏移 0, 1.3846, 3.2308（纹素），权重 0.2270, 0.3162, 0.0703 —— 9 个权重只要 5 次采样
        half4 Blur1D(float2 uv, float2 dir)
        {
            const float o1 = 1.3846153846, o2 = 3.2307692308;
            const half  w0 = 0.2270270270, w1 = 0.3162162162, w2 = 0.0702702703;
            float2 du = dir * _BlitTexture_TexelSize.xy * _Spread;
            half4 c = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv) * w0;
            c += SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + du * o1) * w1;
            c += SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv - du * o1) * w1;
            c += SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + du * o2) * w2;
            c += SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv - du * o2) * w2;
            return c;
        }
        //#endregion

        half4 FragH(Varyings input) : SV_Target
        {
            UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
            return Blur1D(input.texcoord, float2(1, 0));
        }
        half4 FragV(Varyings input) : SV_Target
        {
            UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
            return Blur1D(input.texcoord, float2(0, 1));
        }
        ENDHLSL

        Pass
        {
            Name "BlurH"
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment FragH
            ENDHLSL
        }
        Pass
        {
            Name "BlurV"
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment FragV
            ENDHLSL
        }
    }
}
