// 案例 4.1：在 Shader 里画函数曲线 —— 调试数学函数最直观的办法。
Shader "Cookbook/Ch04/FunctionPlot"
{
    Properties
    {
        [Enum(Steps,0,Repeat,1,Shapes,2)] _Mode ("Curve Set", Float) = 0
        _View ("View (xMin, xMax, yMin, yMax)", Vector) = (-0.2, 1.2, -0.2, 1.2)
        _LineWidth ("Line Width (px)", Float) = 3
        _ColorA ("Curve A", Color) = (0.91, 0.45, 0.23, 1)
        _ColorB ("Curve B", Color) = (0.12, 0.42, 0.56, 1)
        _ColorC ("Curve C", Color) = (0.18, 0.49, 0.34, 1)
        _Paper ("Paper", Color) = (0.98, 0.98, 0.97, 1)
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
                float  _Mode;
                float4 _View;
                float  _LineWidth;
                half4  _ColorA, _ColorB, _ColorC, _Paper;
            CBUFFER_END

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
                    if (k == 1) return frac(x * 2.0);
                    return abs(frac(x) - 0.5) * 2.0;
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
            float PlotCurve(int mode, int k, float2 q, float pixel)
            {
                float2 a = float2(q.x - pixel, Curve(mode, k, q.x - pixel));
                float2 b = float2(q.x + pixel, Curve(mode, k, q.x + pixel));
                float dist = SdSegment(q, a, b);
                return saturate(_LineWidth * 0.5 + 0.5 - dist / pixel);
            }

            // 到 d=0 处一条宽 widthPx 像素的线
            float LineAt(float d, float pixel, float widthPx)
            {
                return saturate(widthPx * 0.5 + 0.5 - abs(d) / pixel);
            }

            // 每隔 spacing 一条网格线：frac 把坐标折回到最近网格线附近
            float GridLine(float v, float spacing, float pixel, float widthPx)
            {
                float d = (frac(v / spacing + 0.5) - 0.5) * spacing;
                return LineAt(d, pixel, widthPx);
            }
            //#endregion

            half4 frag (Varyings input) : SV_Target
            {
                // UV [0,1] → 绘图坐标
                float2 q = float2(lerp(_View.x, _View.y, input.uv.x), lerp(_View.z, _View.w, input.uv.y));
                float pixel = fwidth(q.x);                 // 一个像素对应多少绘图单位

                half3 col = _Paper.rgb;
                col = lerp(col, half3(0.82, 0.85, 0.88), max(GridLine(q.x, 0.25, pixel, 1), GridLine(q.y, 0.25, pixel, 1)));
                col = lerp(col, half3(0.35, 0.38, 0.42), max(LineAt(q.x, pixel, 1.5), LineAt(q.y, pixel, 1.5)));  // 坐标轴
                int mode = (int)_Mode;
                col = lerp(col, _ColorC.rgb, PlotCurve(mode, 2, q, pixel));
                col = lerp(col, _ColorB.rgb, PlotCurve(mode, 1, q, pixel));
                col = lerp(col, _ColorA.rgb, PlotCurve(mode, 0, q, pixel));
                return half4(col, 1);
            }
            ENDHLSL
        }
    }
}
