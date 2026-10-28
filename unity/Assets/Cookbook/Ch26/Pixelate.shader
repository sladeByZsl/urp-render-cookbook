// 案例 26.7：像素化。把 UV 吸附到“大像素”中心，用点采样取色；再在 sRGB 空间做色阶量化 + Bayer 抖动。
Shader "Cookbook/Ch26/Pixelate"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        ZTest Always ZWrite Off Cull Off
        Pass
        {
            Name "Pixelate"
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float4 _PixelateParams;   // x 像素尺寸, y 色阶数, z 抖动强度

            // 4×4 Bayer 矩阵，返回 [0,1) 的阈值
            float Bayer4(uint2 p)
            {
                static const float m[16] = { 0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5 };
                return m[(p.y & 3) * 4 + (p.x & 3)] / 16.0;
            }

            //#region frag
            half4 Frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                float2 screen = _ScreenParams.xy;
                float size = _PixelateParams.x;

                // 1) 当前像素属于哪个“大像素”，取它中心的颜色（点采样，避免边缘被双线性混色）
                float2 block = floor(input.texcoord * screen / size);
                float2 uv = (block + 0.5) * size / screen;
                half3 c = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_PointClamp, uv).rgb;

                // 2) 色阶量化：在 sRGB 空间均匀分级（线性空间分级会让暗部台阶过粗）
                float levels = _PixelateParams.y;
                if (levels > 0.5)
                {
                    half3 s = LinearToSRGB(saturate(c));
                    float threshold = (Bayer4((uint2)block) - 0.5) * _PixelateParams.z;   // 以大像素为单位抖动
                    s = floor(s * (levels - 1.0) + 0.5 + threshold) / (levels - 1.0);
                    c = SRGBToLinear(saturate(s));
                }
                return half4(c, 1.0);
            }
            //#endregion
            ENDHLSL
        }
    }
}
