// 案例 4.10：Bayer 有序抖动 —— 用少量颜色表现连续渐变。
Shader "Cookbook/Ch04/BayerDither"
{
    Properties
    {
        [Enum(Threshold,0,Bayer2x2,1,Bayer4x4,2,Bayer8x8,3)] _Mode ("Mode", Float) = 2
        [IntRange] _Levels ("Color Levels", Range(2, 8)) = 2
        _Resolution ("Virtual Resolution", Float) = 128
        _Dark ("Dark", Color) = (0.10, 0.13, 0.12, 1)
        _Light ("Light", Color) = (0.86, 0.90, 0.78, 1)
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        Pass
        {
            Name "Unlit"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex ProceduralVert
            #pragma fragment frag
            #include "Assets/Cookbook/Ch04/ProceduralCommon.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float _Mode, _Levels, _Resolution;
                half4 _Dark, _Light;
            CBUFFER_END

            // 要被抖动的“原图”：左→右的灰阶渐变 + 一个假光照的球
            float SourceImage(float2 uv)
            {
                float v = uv.x;
                float2 p = (uv - float2(0.5, 0.55)) / 0.32;
                float r2 = dot(p, p);
                if (r2 < 1.0)
                {
                    float3 n = float3(p.x, p.y, sqrt(1.0 - r2));
                    v = saturate(dot(n, normalize(float3(-0.5, 0.6, 0.65)))) * 0.95 + 0.03;
                }
                return v;
            }

            half4 frag (Varyings input) : SV_Target
            {
                // 把面片划成 _Resolution×_Resolution 个“虚拟像素”：每个虚拟像素取一个值、用一个阈值。
                // 这样抖动图案贴在面片上、大小可控；想贴在屏幕上就改用 input.positionCS.xy（单位：屏幕像素）
                float2 cellPx = floor(input.uv * _Resolution);
                float v = SourceImage((cellPx + 0.5) / _Resolution);

                //#region dither
                uint2 pixel = (uint2)cellPx;
                float threshold = 0.5;                                       // 模式 0：所有像素同一个阈值
                if (_Mode > 0.5) threshold = BayerThreshold(pixel, (uint)_Mode);  // 1→2×2, 2→4×4, 3→8×8
                // 量化到 _Levels 级：先放大到 [0, L-1]，加上阈值后向下取整
                float L = _Levels - 1.0;
                float q = floor(v * L + threshold) / L;
                //#endregion
                return half4(lerp(_Dark.rgb, _Light.rgb, saturate(q)), 1);
            }
            ENDHLSL
        }
    }
}
