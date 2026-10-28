// 案例 4.10：Bayer 有序抖动 —— 用少量颜色表现连续渐变。（GLSL 版）
Shader "Cookbook/Ch04/BayerDither"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" }

        Pass
        {
            Name "Unlit"
            Tags { "LightMode"="UniversalForward" }

            GLSLPROGRAM
            #include "Ch04/ProceduralCommon.glsl"

            uniform float _Mode, _Levels, _Resolution;
            uniform vec4  _Dark, _Light;

            #ifdef FRAGMENT
            // 要被抖动的“原图”：左→右的灰阶渐变 + 一个假光照的球
            float SourceImage(vec2 uv)
            {
                float v = uv.x;
                vec2 p = (uv - vec2(0.5, 0.55)) / 0.32;
                float r2 = dot(p, p);
                if (r2 < 1.0)
                {
                    vec3 n = vec3(p.x, p.y, sqrt(1.0 - r2));
                    v = saturate(dot(n, normalize(vec3(-0.5, 0.6, 0.65)))) * 0.95 + 0.03;
                }
                return v;
            }

            void main()
            {
                // 把面片划成 _Resolution×_Resolution 个“虚拟像素”：每个虚拟像素取一个值、用一个阈值。
                // 这样抖动图案贴在面片上、大小可控；想贴在屏幕上就改用 gl_FragCoord.xy（单位：屏幕像素）
                vec2 cellPx = floor(uv * _Resolution);
                float v = SourceImage((cellPx + 0.5) / _Resolution);

                //#region dither
                uvec2 pixel = uvec2(cellPx);
                float threshold = 0.5;                                       // 模式 0：所有像素同一个阈值
                if (_Mode > 0.5) threshold = BayerThreshold(pixel, uint(_Mode));  // 1→2×2, 2→4×4, 3→8×8
                // 量化到 _Levels 级：先放大到 [0, L-1]，加上阈值后向下取整
                float L = _Levels - 1.0;
                float q = floor(v * L + threshold) / L;
                //#endregion
                fragColor = vec4(mix(_Dark.rgb, _Light.rgb, saturate(q)), 1.0);
            }
            #endif
            ENDGLSL
        }
    }
}
