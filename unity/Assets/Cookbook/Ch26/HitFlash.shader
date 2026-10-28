// 案例 26.10：受击红屏——屏幕边缘的血色晕染 + 噪声“血丝” + 整体轻微压暗去色。
Shader "Cookbook/Ch26/HitFlash"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        ZTest Always ZWrite Off Cull Off
        Pass
        {
            Name "HitFlash"
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float4 _HitColor;
            float4 _HitParams;   // x 强度, y 噪声尺度, z 相位

            float Hash21(float2 p)
            {
                p = frac(p * float2(123.34, 456.21));
                p += dot(p, p + 45.32);
                return frac(p.x * p.y);
            }
            float ValueNoise(float2 p)
            {
                float2 i = floor(p), f = frac(p);
                float2 u = f * f * (3.0 - 2.0 * f);
                return lerp(lerp(Hash21(i), Hash21(i + float2(1, 0)), u.x),
                            lerp(Hash21(i + float2(0, 1)), Hash21(i + float2(1, 1)), u.x), u.y);
            }
            float Fbm(float2 p)
            {
                float s = 0, a = 0.5;
                [unroll] for (int k = 0; k < 4; k++) { s += a * ValueNoise(p); p *= 2.03; a *= 0.5; }
                return s;
            }

            //#region frag
            half4 Frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                float2 uv = input.texcoord;
                half4 color = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv);
                float k = _HitParams.x;

                // 1) 椭圆形的边缘遮罩：强度越大，红色往中心侵入越深
                float2 d = (uv - 0.5) * 2.0;
                float r = length(d * float2(1.0, 0.85));

                // 2) 用 fBm 噪声扰动遮罩边界，形成不规则的“血丝”；相位让它在运行时蠕动
                float t = _HitParams.z + _Time.y * 0.6;
                float n = Fbm(uv * _HitParams.y + float2(t, -t * 0.7));
                float inner = lerp(1.25, 0.45, k);
                half edge = smoothstep(inner, inner + 0.55, r + (n - 0.5) * 0.45);

                // 3) 中心区域轻微去色、压暗，模拟“眼前一黑”
                half luma = dot(color.rgb, half3(0.2126, 0.7152, 0.0722));
                half3 dimmed = lerp(color.rgb, luma.xxx * half3(1.0, 0.85, 0.85), 0.35 * k) * (1.0 - 0.2 * k);

                // 4) 边缘：用乘 + 加的组合，暗部也能被染红，亮部不会变成纯色块
                half3 blood = dimmed * _HitColor.rgb * 0.6 + _HitColor.rgb * 0.35;
                color.rgb = lerp(dimmed, blood, edge * saturate(k * 1.5));
                return color;
            }
            //#endregion
            ENDHLSL
        }
    }
}
