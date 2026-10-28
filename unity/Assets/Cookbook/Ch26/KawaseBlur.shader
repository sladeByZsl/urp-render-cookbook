// 案例 26.3：Kawase（Pass 0）与 Dual Kawase（Pass 1 下采样 / Pass 2 上采样）。
Shader "Cookbook/Ch26/KawaseBlur"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        ZTest Always ZWrite Off Cull Off

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

        float4 _BlitTexture_TexelSize;   // 源纹理（_BlitTexture）的纹素大小
        float  _KawaseOffset;            // 由 cmd.SetGlobalFloat 逐次设置，不要放进 Properties

        half4 Tap(float2 uv) { return SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv); }

        //#region kawase
        // 经典 Kawase：在对角线 4 个点各采一次（每次双线性 = 4 个纹素平均），第 i 次迭代偏移 i+0.5
        half4 FragKawase(Varyings input) : SV_Target
        {
            UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
            float2 uv = input.texcoord;
            float2 d = _BlitTexture_TexelSize.xy * _KawaseOffset;
            half4 c = Tap(uv + float2( d.x,  d.y));
            c += Tap(uv + float2(-d.x,  d.y));
            c += Tap(uv + float2( d.x, -d.y));
            c += Tap(uv + float2(-d.x, -d.y));
            return c * 0.25;
        }
        //#endregion

        //#region dual
        // Dual Kawase 下采样：中心权重 4 + 四个对角各 1，共 5 次采样，输出到一半分辨率
        half4 FragDown(Varyings input) : SV_Target
        {
            UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
            float2 uv = input.texcoord;
            float2 h = _BlitTexture_TexelSize.xy * 0.5 * _KawaseOffset;
            half4 c = Tap(uv) * 4.0;
            c += Tap(uv - h);
            c += Tap(uv + h);
            c += Tap(uv + float2(h.x, -h.y));
            c += Tap(uv - float2(h.x, -h.y));
            return c * (1.0 / 8.0);
        }

        // Dual Kawase 上采样：菱形 4 点（权重 1）+ 对角 4 点（权重 2），共 8 次采样，输出到两倍分辨率
        half4 FragUp(Varyings input) : SV_Target
        {
            UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
            float2 uv = input.texcoord;
            float2 h = _BlitTexture_TexelSize.xy * 0.5 * _KawaseOffset;
            half4 c = Tap(uv + float2(-h.x * 2.0, 0.0));
            c += Tap(uv + float2( h.x * 2.0, 0.0));
            c += Tap(uv + float2(0.0, -h.y * 2.0));
            c += Tap(uv + float2(0.0,  h.y * 2.0));
            c += Tap(uv + float2(-h.x,  h.y)) * 2.0;
            c += Tap(uv + float2( h.x,  h.y)) * 2.0;
            c += Tap(uv + float2( h.x, -h.y)) * 2.0;
            c += Tap(uv + float2(-h.x, -h.y)) * 2.0;
            return c * (1.0 / 12.0);
        }
        //#endregion
        ENDHLSL

        Pass
        {
            Name "Kawase"
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment FragKawase
            ENDHLSL
        }
        Pass
        {
            Name "DualDown"
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment FragDown
            ENDHLSL
        }
        Pass
        {
            Name "DualUp"
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment FragUp
            ENDHLSL
        }
    }
}
