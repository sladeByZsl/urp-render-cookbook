// 水彩感：颜料按“透射率^浓度”叠在纸上（Beer–Lambert 式减色），（GLSL 版，对应 Ch15/Watercolor.shader）
// 用噪声扰动色阶边界模拟水渍晕开，边界和轮廓处颜料堆积变深，纸纹让颜料沉淀出颗粒感。
Shader "Cookbook/Ch15/Watercolor"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform vec4 _BaseColor, _ShadowPigment, _PaperColor;
        uniform float _PaperScale;
        uniform float _Bands, _Wobble, _Density, _EdgeDarken, _Granulation;
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            GLSLPROGRAM
            #define NPR_VARYINGS
            #include "Ch15/NPRCommon.glsl"

            uniform sampler2D _NoiseTex;

            #ifdef VERTEX
            void main() { NprVert(); }
            #endif

            #ifdef FRAGMENT
            //#region frag
            vec4 frag()
            {
                vec3 N = normalize(normalWS);
                vec3 V = GetWorldSpaceNormalizeViewDir(positionWS);
                NprLight L = GetNprLight(positionWS, N);

                // 纸纹和水渍噪声都固定在画面上（纸不会跟着物体动）
                vec2 suv = GetNormalizedScreenSpaceUV(gl_FragCoord) * vec2(_ScreenParams.x / _ScreenParams.y, 1.0);
                float wash  = texture(_NoiseTex, suv * 1.3).r - 0.5;                 // 低频：晕染
                float grain = texture(_NoiseTex, suv * _PaperScale * 8.0).r;         // 高频：纸纹

                // 1) 受光 + 噪声扰动，再分成几层“罩染”
                float light = saturate(L.ndotl) * L.shadow + wash * _Wobble;
                float f = saturate(light) * _Bands;
                float fr = fract(f);
                float tone = (floor(f) + smoothstep(0.35, 0.65, fr)) / _Bands;   // 0 = 最暗，1 = 最亮

                // 2) 色阶交界处颜料干后堆积（“水边线”）
                float edge = exp(-pow((fr - 0.5) / 0.12, 2.0)) * step(0.02, f) * step(f, _Bands - 0.02);

                // 3) 轮廓处的颜料堆积：N·V 越小越靠近轮廓，加噪声让边缘不规则
                float rim = smoothstep(0.55, 0.95, 1.0 - saturate(dot(N, V)) + wash * 0.4);

                // 4) 浓度：暗处颜料多，再叠加边缘堆积和纸纹沉淀
                float density = _Density * mix(0.25, 1.0, 1.0 - tone);
                density += (edge * 0.6 + rim) * _EdgeDarken;
                density *= mix(1.0, 0.6 + 0.8 * grain, _Granulation);

                // 5) 暗部换一种偏冷的颜料，然后按 Beer–Lambert：透射率 = 颜料色^浓度
                vec3 pigment = mix(_BaseColor.rgb, _BaseColor.rgb * _ShadowPigment.rgb * 1.6, saturate(1.0 - tone) * 0.7);
                vec3 paper = _PaperColor.rgb * (0.94 + 0.06 * grain);
                vec3 col = paper * pow(saturate(pigment), vec3(max(density, 0.0)));
                return vec4(col, 1.0);
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
