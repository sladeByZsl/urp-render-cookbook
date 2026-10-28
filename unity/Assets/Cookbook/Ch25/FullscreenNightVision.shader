// 案例 25.3：给 URP 自带的 Full Screen Pass Renderer Feature 用的手写 Shader——夜视仪。
// 该 Feature 会把相机颜色拷贝一份，作为 _BlitTexture 传进来，并设置 _BlitScaleBias=(1,1,0,0)，
// 所以直接复用 Blit.hlsl 的 Vert 即可。
Shader "Cookbook/Ch25/FullscreenNightVision"
{
    Properties
    {
        _Gain ("Gain", Range(0.5, 8)) = 3
        _Tint ("Tint", Color) = (0.25, 1, 0.35, 1)
        _ScanlineStrength ("Scanline Strength", Range(0, 1)) = 0.25
        _VignetteRadius ("Vignette Radius", Range(0.2, 1.2)) = 0.75
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        ZTest Always ZWrite Off Cull Off

        Pass
        {
            Name "NightVision"
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float  _Gain;
                float4 _Tint;
                float  _ScanlineStrength;
                float  _VignetteRadius;
            CBUFFER_END

            float Hash12(float2 p)
            {
                float3 p3 = frac(float3(p.xyx) * 0.1031);
                p3 += dot(p3, p3.yzx + 33.33);
                return frac((p3.x + p3.y) * p3.z);
            }

            //#region frag
            half4 Frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                float2 uv = input.texcoord;
                half3 c = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv).rgb;

                // 亮度放大（模拟像增强管），再压一条曲线防止大片死白
                half luma = dot(c, half3(0.2126, 0.7152, 0.0722)) * _Gain;
                luma = luma / (1.0 + luma);

                // 颗粒噪点：按像素坐标取哈希，_Time 让它在运行时闪动（截图时 _Time≈0）
                float2 pixel = uv * _ScreenParams.xy;
                half grain = Hash12(pixel + frac(_Time.y * 13.0) * 517.0) - 0.5;
                luma = saturate(luma + grain * 0.12);

                // 扫描线：每 3 像素一条暗线
                half scan = 1.0 - _ScanlineStrength * step(2.0, fmod(pixel.y, 3.0));

                // 圆形镜筒暗角（按宽高比校正成正圆）
                float2 d = (uv - 0.5) * float2(_ScreenParams.x / _ScreenParams.y, 1.0);
                half vignette = smoothstep(_VignetteRadius, _VignetteRadius - 0.25, length(d));

                half3 result = _Tint.rgb * luma * scan * vignette;
                return half4(result, 1.0);
            }
            //#endregion
            ENDHLSL
        }
    }
}
