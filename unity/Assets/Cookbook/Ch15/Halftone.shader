// 半调网点（Halftone）：在屏幕上铺一张旋转过的网格，每格画一个圆点，
// 圆点面积 = 该处“墨量”。单色模式只用黑墨；CMYK 模式四色各自用不同网角叠印。
Shader "Cookbook/Ch15/Halftone"
{
    Properties
    {
        _BaseColor ("Base Color", Color) = (0.85, 0.3, 0.25, 1)
        [KeywordEnum(Off, Mono, CMYK)] _Style ("Style", Float) = 1
        _CellSize ("Cell Size (pixels)", Range(3, 32)) = 8
        _PaperColor ("Paper Color", Color) = (0.97, 0.95, 0.9, 1)
        _BlackGen ("Black Generation", Range(0, 1)) = 0.8
        _Contrast ("Tone Contrast", Range(0.5, 2)) = 1.15
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        CBUFFER_START(UnityPerMaterial)
            half4 _BaseColor, _PaperColor;
            float _CellSize;
            half  _BlackGen, _Contrast;
        CBUFFER_END
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            HLSLPROGRAM
            #pragma vertex NprVert
            #pragma fragment frag
            #pragma shader_feature_local_fragment _STYLE_OFF _STYLE_MONO _STYLE_CMYK
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #include "Assets/Cookbook/Ch15/NPRCommon.hlsl"

            //#region dot
            // 返回当前像素被网点覆盖的比例（0..1，已抗锯齿）
            // pixel：屏幕像素坐标；cell：网格边长（像素）；angle：网角（度）；ink：该处墨量 0..1
            half HalftoneDot(float2 pixel, float cell, float angle, half ink)
            {
                float s, c;
                sincos(radians(angle), s, c);
                float2 p = mul(float2x2(c, -s, s, c), pixel) / cell;   // 旋转后的网格坐标
                float2 local = frac(p) - 0.5;                           // 格子内坐标，中心为 0
                float d = length(local);
                // 圆面积 πr² 与格子面积 1 之比 = 墨量，所以半径与墨量的平方根成正比
                float r = sqrt(saturate(ink) / PI);
                float aa = max(fwidth(d), 1e-4);                        // 约等于一个像素宽
                return 1.0 - smoothstep(r - aa, r + aa, d);
            }
            //#endregion

            //#region frag
            half4 frag(NprVaryings i) : SV_Target
            {
                float3 N = normalize(i.normalWS);
                NprLight L = GetNprLight(i.positionWS, N);
                half3 lit = _BaseColor.rgb * (saturate(L.ndotl) * L.shadow * L.color + SampleSH(N));
                lit = saturate(lit);
            #if defined(_STYLE_OFF)
                return half4(lit, 1);
            #else
                // 加一点对比度，印刷品的网点通常比连续色调“硬”
                lit = saturate((lit - 0.5h) * _Contrast + 0.5h);
                float2 px = i.positionCS.xy;
              #if defined(_STYLE_MONO)
                // 单色版只表现明暗：用光照本身的亮度，本色只轻微参与，否则深色物体会糊成一片灰
                half3 lighting = saturate(L.ndotl) * L.shadow * L.color + SampleSH(N);
                half tone = Luminance(saturate(lighting)) * lerp(1.0h, Luminance(_BaseColor.rgb), 0.3h);
                half ink = 1.0h - saturate((tone - 0.5h) * _Contrast + 0.5h);
                half cover = HalftoneDot(px, _CellSize, 45, ink);
                return half4(lerp(_PaperColor.rgb, half3(0.08, 0.08, 0.1), cover), 1);
              #else
                // RGB → CMY，再把三色共同的“灰”部分交给黑墨（K），减少用墨、让暗部更干净
                half3 cmy = 1.0h - lit;
                half k = min(cmy.r, min(cmy.g, cmy.b)) * _BlackGen;
                cmy = (cmy - k) / max(1.0h - k, 1e-3h);

                // 经典网角：C 15°、M 75°、Y 0°、K 45°，错开角度避免摩尔纹
                half c  = HalftoneDot(px, _CellSize, 15, cmy.r);
                half m  = HalftoneDot(px, _CellSize, 75, cmy.g);
                half y  = HalftoneDot(px, _CellSize,  0, cmy.b);
                half kk = HalftoneDot(px, _CellSize, 45, k);

                // 减色叠印：每种墨把纸的颜色乘上自己的透射色
                half3 col = _PaperColor.rgb;
                col *= lerp(1.0h, half3(0.0, 0.66, 0.92), c);
                col *= lerp(1.0h, half3(0.92, 0.1, 0.55), m);
                col *= lerp(1.0h, half3(1.0, 0.92, 0.05), y);
                col *= lerp(1.0h, half3(0.1, 0.1, 0.12), kk);
                return half4(col, 1);
              #endif
            #endif
            }
            //#endregion
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0
            HLSLPROGRAM
            #pragma vertex NprShadowVert
            #pragma fragment NprNullFrag
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Assets/Cookbook/Ch15/NPRCommon.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            HLSLPROGRAM
            #pragma vertex NprDepthVert
            #pragma fragment NprNullFrag
            #include "Assets/Cookbook/Ch15/NPRCommon.hlsl"
            ENDHLSL
        }
    }
}
