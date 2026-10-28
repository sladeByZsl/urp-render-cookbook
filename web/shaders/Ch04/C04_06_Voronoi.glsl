// 案例 4.6：Voronoi 细胞 —— F1 距离、F2-F1 边界、按格子 id 上色。（GLSL 版）
Shader "Cookbook/Ch04/Voronoi"
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

            uniform float _Mode, _Scale, _Phase, _Speed, _EdgeWidth;
            uniform vec4  _ColorA, _ColorB, _EdgeColor;

            #ifdef FRAGMENT
            void main()
            {
                vec2 p = uv * _Scale;
                float f1, f2; vec2 cell;
                Voronoi(p, _Phase + _Time.y * _Speed, f1, f2, cell);

                //#region shade
                vec3 col;
                if (_Mode < 0.5)
                {
                    // F1：到最近特征点的距离 → 一个个“圆锥”，加等高线更容易看出形状
                    col = mix(_ColorA.rgb, _ColorB.rgb, saturate(f1 * 1.4));
                    col *= 0.85 + 0.15 * step(0.5, fract(f1 * 8.0));
                    col = mix(col, _EdgeColor.rgb, 1.0 - smoothstep(0.03, 0.05, f1));   // 特征点
                }
                else if (_Mode < 1.5)
                {
                    // F2 - F1：两个最近点距离相等的地方就是细胞边界，那里差值趋于 0
                    float e = f2 - f1;
                    col = mix(_EdgeColor.rgb, _ColorB.rgb, smoothstep(0.0, _EdgeWidth * 2.0, e));
                }
                else
                {
                    // 用最近格子的编号再哈希一次，每个细胞一个固定颜色
                    float h = Hash21(cell + 31.7);
                    col = mix(_ColorA.rgb, _ColorB.rgb, h);
                    // 用到边界的真实距离做明暗和描边：中心亮、边缘暗，像鹅卵石
                    float border = VoronoiBorder(p, _Phase + _Time.y * _Speed);
                    col *= mix(0.7, 1.1, saturate(border * 2.5));
                    float aa = fwidth(border);
                    col = mix(_EdgeColor.rgb, col, smoothstep(_EdgeWidth * 0.5 - aa, _EdgeWidth * 0.5 + aa, border));
                }
                //#endregion
                fragColor = vec4(col, 1.0);
            }
            #endif
            ENDGLSL
        }
    }
}
