// 案例 4.6：Voronoi 细胞 —— F1 距离、F2-F1 边界、按格子 id 上色。
Shader "Cookbook/Ch04/Voronoi"
{
    Properties
    {
        [Enum(F1,0,Edges,1,Cells,2)] _Mode ("Mode", Float) = 2
        _Scale ("Scale", Float) = 6
        _Phase ("Phase (for stills)", Float) = 0
        _Speed ("Animate Speed", Float) = 1
        _EdgeWidth ("Edge Width", Range(0.001, 0.3)) = 0.06
        _ColorA ("Color A", Color) = (0.12, 0.42, 0.56, 1)
        _ColorB ("Color B", Color) = (0.95, 0.80, 0.55, 1)
        _EdgeColor ("Edge Color", Color) = (0.08, 0.09, 0.11, 1)
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
                float _Mode, _Scale, _Phase, _Speed, _EdgeWidth;
                half4 _ColorA, _ColorB, _EdgeColor;
            CBUFFER_END

            half4 frag (Varyings input) : SV_Target
            {
                float2 p = input.uv * _Scale;
                float f1, f2; float2 cell;
                Voronoi(p, _Phase + _Time.y * _Speed, f1, f2, cell);

                //#region shade
                half3 col;
                if (_Mode < 0.5)
                {
                    // F1：到最近特征点的距离 → 一个个“圆锥”，加等高线更容易看出形状
                    col = lerp(_ColorA.rgb, _ColorB.rgb, saturate(f1 * 1.4));
                    col *= 0.85 + 0.15 * step(0.5, frac(f1 * 8.0));
                    col = lerp(col, _EdgeColor.rgb, 1.0 - smoothstep(0.03, 0.05, f1));   // 特征点
                }
                else if (_Mode < 1.5)
                {
                    // F2 - F1：两个最近点距离相等的地方就是细胞边界，那里差值趋于 0
                    float e = f2 - f1;
                    col = lerp(_EdgeColor.rgb, _ColorB.rgb, smoothstep(0.0, _EdgeWidth * 2.0, e));
                }
                else
                {
                    // 用最近格子的编号再哈希一次，每个细胞一个固定颜色
                    float h = Hash21(cell + 31.7);
                    col = lerp(_ColorA.rgb, _ColorB.rgb, h);
                    // 用到边界的真实距离做明暗和描边：中心亮、边缘暗，像鹅卵石
                    float border = VoronoiBorder(p, _Phase + _Time.y * _Speed);
                    col *= lerp(0.7, 1.1, saturate(border * 2.5));
                    float aa = fwidth(border);
                    col = lerp(_EdgeColor.rgb, col, smoothstep(_EdgeWidth * 0.5 - aa, _EdgeWidth * 0.5 + aa, border));
                }
                //#endregion
                return half4(col, 1);
            }
            ENDHLSL
        }
    }
}
