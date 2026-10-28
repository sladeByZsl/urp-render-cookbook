// 案例 4.1：在 Shader 里画函数曲线 —— 调试数学函数最直观的办法。（GLSL 版）
Shader "Cookbook/Ch04/FunctionPlot"
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

            uniform float _Mode;
            uniform vec4  _View;
            uniform float _LineWidth;
            uniform vec4  _ColorA, _ColorB, _ColorC, _Paper;

            #ifdef FRAGMENT
            //#region curves
            // 第 k 条曲线 y = f(x)。改这里就能画任意函数
            float Curve(int mode, int k, float x)
            {
                if (mode == 0)          // 阈值类：step / smoothstep / 线性 step
                {
                    if (k == 0) return step(0.5, x);
                    if (k == 1) return smoothstep(0.2, 0.8, x);
                    return LinearStep(0.2, 0.8, x);
                }
                if (mode == 1)          // 重复类：floor 阶梯 / frac 锯齿 / 三角波
                {
                    if (k == 0) return floor(x * 4.0) / 4.0;
                    if (k == 1) return fract(x * 2.0);
                    return abs(fract(x) - 0.5) * 2.0;
                }
                // 形状类：脉冲（两个 smoothstep 相减）/ 正弦重映射 / 幂函数
                if (k == 0) return smoothstep(0.25, 0.35, x) - smoothstep(0.65, 0.75, x);
                if (k == 1) return 0.5 + 0.5 * sin(x * TWO_PI * 2.0);
                return x * x * x;
            }
            //#endregion

            //#region plot
            // 抗锯齿画线：把曲线在当前像素附近近似成一小段折线（左右各一个像素），
            // 求到这段线段的距离，再换算成“像素单位”。跳变处线段几乎竖直，竖线也能自然连上
            float PlotCurve(int mode, int k, vec2 q, float pixel)
            {
                vec2 a = vec2(q.x - pixel, Curve(mode, k, q.x - pixel));
                vec2 b = vec2(q.x + pixel, Curve(mode, k, q.x + pixel));
                float dist = SdSegment(q, a, b);
                return saturate(_LineWidth * 0.5 + 0.5 - dist / pixel);
            }

            // 到 d=0 处一条宽 widthPx 像素的线
            float LineAt(float d, float pixel, float widthPx)
            {
                return saturate(widthPx * 0.5 + 0.5 - abs(d) / pixel);
            }

            // 每隔 spacing 一条网格线：fract 把坐标折回到最近网格线附近
            float GridLine(float v, float spacing, float pixel, float widthPx)
            {
                float d = (fract(v / spacing + 0.5) - 0.5) * spacing;
                return LineAt(d, pixel, widthPx);
            }
            //#endregion

            void main()
            {
                // UV [0,1] → 绘图坐标
                vec2 q = vec2(mix(_View.x, _View.y, uv.x), mix(_View.z, _View.w, uv.y));
                float pixel = fwidth(q.x);                 // 一个像素对应多少绘图单位

                vec3 col = _Paper.rgb;
                col = mix(col, vec3(0.82, 0.85, 0.88), max(GridLine(q.x, 0.25, pixel, 1.0), GridLine(q.y, 0.25, pixel, 1.0)));
                col = mix(col, vec3(0.35, 0.38, 0.42), max(LineAt(q.x, pixel, 1.5), LineAt(q.y, pixel, 1.5)));  // 坐标轴
                int mode = int(_Mode);
                col = mix(col, _ColorC.rgb, PlotCurve(mode, 2, q, pixel));
                col = mix(col, _ColorB.rgb, PlotCurve(mode, 1, q, pixel));
                col = mix(col, _ColorA.rgb, PlotCurve(mode, 0, q, pixel));
                fragColor = vec4(col, 1.0);
            }
            #endif
            ENDGLSL
        }
    }
}
