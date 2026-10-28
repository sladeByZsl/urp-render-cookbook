// 半调网点（Halftone）：在屏幕上铺一张旋转过的网格，每格画一个圆点，（GLSL 版，对应 Ch15/Halftone.shader）
// 圆点面积 = 该处“墨量”。单色模式只用黑墨；CMYK 模式四色各自用不同网角叠印。
Shader "Cookbook/Ch15/Halftone"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform vec4 _BaseColor, _PaperColor;
        uniform float _CellSize;
        uniform float _BlackGen, _Contrast;
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            GLSLPROGRAM
            #pragma shader_feature_local_fragment _STYLE_OFF _STYLE_MONO _STYLE_CMYK
            #define NPR_VARYINGS
            #include "Ch15/NPRCommon.glsl"

            #ifdef VERTEX
            void main() { NprVert(); }
            #endif

            #ifdef FRAGMENT
            //#region dot
            // 返回当前像素被网点覆盖的比例（0..1，已抗锯齿）
            // pixel：屏幕像素坐标；cell：网格边长（像素）；angle：网角（度）；ink：该处墨量 0..1
            float HalftoneDot(vec2 pixel, float cell, float angle, float ink)
            {
                float s = sin(radians(angle)), c = cos(radians(angle));
                // HLSL 的 mul(float2x2(c, -s, s, c), p)：float2x2 按行构造，GLSL 的 mat2 按列，所以写成 p * mat2(...)
                vec2 p = (pixel * mat2(c, -s, s, c)) / cell;   // 旋转后的网格坐标
                vec2 local = fract(p) - 0.5;                    // 格子内坐标，中心为 0
                float d = length(local);
                // 圆面积 πr² 与格子面积 1 之比 = 墨量，所以半径与墨量的平方根成正比
                float r = sqrt(saturate(ink) / PI);
                float aa = max(fwidth(d), 1e-4);                // 约等于一个像素宽
                return 1.0 - smoothstep(r - aa, r + aa, d);
            }
            //#endregion

            //#region frag
            vec4 frag()
            {
                vec3 N = normalize(normalWS);
                NprLight L = GetNprLight(positionWS, N);
                vec3 lit = _BaseColor.rgb * (saturate(L.ndotl) * L.shadow * L.color + SampleSH(N));
                lit = saturate(lit);
            #if defined(_STYLE_OFF)
                return vec4(lit, 1.0);
            #else
                // 加一点对比度，印刷品的网点通常比连续色调“硬”
                lit = saturate((lit - 0.5) * _Contrast + 0.5);
                vec2 px = gl_FragCoord.xy;                      // = HLSL 的 i.positionCS.xy（像素坐标）
              #if defined(_STYLE_MONO)
                // 单色版只表现明暗：用光照本身的亮度，本色只轻微参与，否则深色物体会糊成一片灰
                vec3 lighting = saturate(L.ndotl) * L.shadow * L.color + SampleSH(N);
                float tone = Luminance(saturate(lighting)) * mix(1.0, Luminance(_BaseColor.rgb), 0.3);
                float ink = 1.0 - saturate((tone - 0.5) * _Contrast + 0.5);
                float cover = HalftoneDot(px, _CellSize, 45.0, ink);
                return vec4(mix(_PaperColor.rgb, vec3(0.08, 0.08, 0.1), cover), 1.0);
              #else
                // RGB → CMY，再把三色共同的“灰”部分交给黑墨（K），减少用墨、让暗部更干净
                vec3 cmy = 1.0 - lit;
                float k = min(cmy.r, min(cmy.g, cmy.b)) * _BlackGen;
                cmy = (cmy - k) / max(1.0 - k, 1e-3);

                // 经典网角：C 15°、M 75°、Y 0°、K 45°，错开角度避免摩尔纹
                float c  = HalftoneDot(px, _CellSize, 15.0, cmy.r);
                float m  = HalftoneDot(px, _CellSize, 75.0, cmy.g);
                float y  = HalftoneDot(px, _CellSize,  0.0, cmy.b);
                float kk = HalftoneDot(px, _CellSize, 45.0, k);

                // 减色叠印：每种墨把纸的颜色乘上自己的透射色
                vec3 col = _PaperColor.rgb;
                col *= mix(vec3(1.0), vec3(0.0, 0.66, 0.92), c);
                col *= mix(vec3(1.0), vec3(0.92, 0.1, 0.55), m);
                col *= mix(vec3(1.0), vec3(1.0, 0.92, 0.05), y);
                col *= mix(vec3(1.0), vec3(0.1, 0.1, 0.12), kk);
                return vec4(col, 1.0);
              #endif
            #endif
            }
            //#endregion
            void main() { fragColor = frag(); }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0
            GLSLPROGRAM
            #define NPR_SHADOW_PASS
            #include "Ch15/NPRCommon.glsl"
            ENDGLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            GLSLPROGRAM
            #define NPR_DEPTH_PASS
            #include "Ch15/NPRCommon.glsl"
            ENDGLSL
        }
    }
}
