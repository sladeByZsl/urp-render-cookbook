// 案例 26.4：自制 Bloom。Pass 0 预过滤，1 下采样，2 上采样合并，3 合成。
Shader "Cookbook/Ch26/MyBloom"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        ZTest Always ZWrite Off Cull Off

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

        float4 _BlitTexture_TexelSize;
        float4 _BloomParams;            // x 阈值, y 膝宽, z scatter, w 强度
        float4 _BloomTint;
        float  _BloomDebugView;         // 0 正常, 1 只看预过滤, 2 只看泛光
        TEXTURE2D_X(_BloomLowMip);      // 上采样时的“下一层”（全局纹理）
        TEXTURE2D_X(_BloomTex);         // 合成时的最终泛光（全局纹理）

        half3 Tap(float2 uv) { return SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv).rgb; }

        //#region prefilter
        half4 FragPrefilter(Varyings input) : SV_Target
        {
            UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
            float2 uv = input.texcoord;
            float2 t = _BlitTexture_TexelSize.xy;
            // 4 次双线性 = 4×4 纹素的盒式平均，顺便完成 2 倍降采样
            half3 c = (Tap(uv + t * float2(-1, -1)) + Tap(uv + t * float2(1, -1))
                     + Tap(uv + t * float2(-1,  1)) + Tap(uv + t * float2(1,  1))) * 0.25;
            c = min(c, 65000.0);                       // 防止 Inf 一路扩散

            // 软阈值（二次曲线过渡的“膝”）：亮度 b 在 [T-K, T+K] 之间平滑过渡
            half threshold = _BloomParams.x, knee = _BloomParams.y;
            half b = Max3(c.r, c.g, c.b);
            half soft = clamp(b - threshold + knee, 0.0, 2.0 * knee);
            soft = soft * soft / (4.0 * knee + 1e-4);
            half contribution = max(b - threshold, soft) / max(b, 1e-4);
            return half4(c * contribution, 1.0);
        }
        //#endregion

        //#region down
        // 13 次采样下采样（Jimenez 2014, Next Generation Post Processing in Call of Duty）：
        // 中心 4 点权重 0.5，四个角上的 2×2 小方块各 0.125，能明显抑制高亮像素的闪烁
        half4 FragDown(Varyings input) : SV_Target
        {
            UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
            float2 uv = input.texcoord;
            float2 t = _BlitTexture_TexelSize.xy;
            half3 A = Tap(uv + t * float2(-2, -2)), B = Tap(uv + t * float2(0, -2)), C = Tap(uv + t * float2(2, -2));
            half3 D = Tap(uv + t * float2(-1, -1)), E = Tap(uv + t * float2(1, -1));
            half3 F = Tap(uv + t * float2(-2,  0)), G = Tap(uv),                      H = Tap(uv + t * float2(2,  0));
            half3 I = Tap(uv + t * float2(-1,  1)), J = Tap(uv + t * float2(1,  1));
            half3 K = Tap(uv + t * float2(-2,  2)), L = Tap(uv + t * float2(0,  2)), M = Tap(uv + t * float2(2,  2));
            half3 c = (D + E + I + J) * (0.5 / 4.0);
            c += (A + B + G + F) * (0.125 / 4.0);
            c += (B + C + H + G) * (0.125 / 4.0);
            c += (F + G + L + K) * (0.125 / 4.0);
            c += (G + H + M + L) * (0.125 / 4.0);
            return half4(c, 1.0);
        }
        //#endregion

        //#region up
        // 上采样：低一层用 3×3 帐篷滤波放大，再与本层按 scatter 插值
        half4 FragUp(Varyings input) : SV_Target
        {
            UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
            float2 uv = input.texcoord;
            float2 t = _BlitTexture_TexelSize.xy;
            #define LOW(o) SAMPLE_TEXTURE2D_X(_BloomLowMip, sampler_LinearClamp, uv + t * (o)).rgb
            half3 low = LOW(float2(-1, -1)) + LOW(float2(1, -1)) + LOW(float2(-1, 1)) + LOW(float2(1, 1));
            low += (LOW(float2(0, -1)) + LOW(float2(-1, 0)) + LOW(float2(1, 0)) + LOW(float2(0, 1))) * 2.0;
            low += LOW(float2(0, 0)) * 4.0;
            low *= 1.0 / 16.0;
            #undef LOW
            half3 high = Tap(uv);
            return half4(lerp(high, low, _BloomParams.z), 1.0);
        }
        //#endregion

        //#region composite
        half4 FragComposite(Varyings input) : SV_Target
        {
            UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
            float2 uv = input.texcoord;
            half4 color = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv);
            half3 bloom = SAMPLE_TEXTURE2D_X(_BloomTex, sampler_LinearClamp, uv).rgb * _BloomTint.rgb * _BloomParams.w;
            if (_BloomDebugView > 0.5) return half4(bloom, 1.0);   // 调试：只看泛光
            color.rgb += bloom;                                     // 线性 HDR 空间里直接相加
            return color;
        }
        //#endregion
        ENDHLSL

        Pass { Name "Prefilter"
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment FragPrefilter
            ENDHLSL
        }
        Pass { Name "Down"
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment FragDown
            ENDHLSL
        }
        Pass { Name "Up"
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment FragUp
            ENDHLSL
        }
        Pass { Name "Composite"
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment FragComposite
            ENDHLSL
        }
    }
}
