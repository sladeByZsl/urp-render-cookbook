// 案例 4.4：极坐标图案 —— 花瓣、螺旋、旋转的放射光。
Shader "Cookbook/Ch04/Polar"
{
    Properties
    {
        [Enum(Flower,0,Spiral,1,Sunburst,2)] _Mode ("Mode", Float) = 0
        _Count ("Petals / Arms / Rays", Float) = 6
        _Twist ("Spiral Twist", Float) = 1.5
        _Angle ("Angle (deg)", Float) = 0
        _Speed ("Rotate Speed (deg/s)", Float) = 30
        _ColorA ("Color A", Color) = (0.91, 0.45, 0.23, 1)
        _ColorB ("Color B", Color) = (0.12, 0.42, 0.56, 1)
        _BgColor ("Background", Color) = (0.97, 0.95, 0.90, 1)
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
                float _Mode, _Count, _Twist, _Angle, _Speed;
                half4 _ColorA, _ColorB, _BgColor;
            CBUFFER_END

            //#region flower
            half3 Flower(float2 p)
            {
                float2 pol = ToPolar(p);
                float theta = pol.y * TWO_PI;
                // 半径随角度起伏：r(θ) = 基础半径 + 振幅·cos(Nθ)，N 片花瓣
                float edge = 0.55 + 0.25 * cos(_Count * theta);
                float petal = FillAA(pol.x - edge);
                // 花瓣内部再按半径做一层渐变，中心是一颗小圆
                half3 col = lerp(_BgColor.rgb, lerp(_ColorA.rgb, _ColorA.rgb * 0.55, pol.x / edge), petal);
                col = lerp(col, _ColorB.rgb, FillAA(SdCircle(p, 0.2)));
                return col;
            }
            //#endregion

            //#region spiral
            half3 Spiral(float2 p)
            {
                float2 pol = ToPolar(p);
                // 角度 + log(半径)：沿径向每走 e 倍，条纹转过 _Twist 圈 → 对数螺线
                float s = frac(pol.y * _Count + log(max(pol.x, 1e-4)) * _Twist);
                float band = abs(s - 0.5) * 2.0;
                float aa = fwidth(band);
                float m = smoothstep(0.5 - aa, 0.5 + aa, band);
                half3 col = lerp(_ColorA.rgb, _ColorB.rgb, m);
                // 中心处条纹无限变细，必然出摩尔纹；用一个圆盖住
                return lerp(col, _BgColor.rgb, FillAA(SdCircle(p, 0.06)));
            }
            //#endregion

            //#region sunburst
            half3 Sunburst(float2 p)
            {
                float2 pol = ToPolar(p);
                float t = pol.y * _Count;                  // 每条光芒占 1 个单位
                float tri = abs(frac(t) - 0.5) * 2.0;
                // 坑：pol.y 在 +X 轴处从 1 跳回 0，fwidth 会在那条线上暴涨，画出一道“裂缝”。
                // 解决：用另一个在别处断开的角度（偏移半圈）求导，两者取小。
                float a2 = frac(pol.y + 0.5) * _Count;
                float aa = min(fwidth(t), fwidth(a2)) * 2.0;
                float ray = smoothstep(0.5 - aa, 0.5 + aa, tri);
                half3 col = lerp(_ColorA.rgb, _ColorB.rgb, ray);
                // 向外渐暗 + 中心太阳
                col *= lerp(1.15, 0.55, saturate(pol.x));
                return lerp(col, half3(1.0, 0.85, 0.45), FillAA(SdCircle(p, 0.22)));
            }
            //#endregion

            half4 frag (Varyings input) : SV_Target
            {
                float2 p = (input.uv - 0.5) * 2.0;
                // 旋转矩阵：静态角度 + 随时间转动（截图时 _Time≈0，只用 _Angle）
                p = Rotate2D(p, radians(_Angle + _Speed * _Time.y));
                half3 col;
                if (_Mode < 0.5)      col = Flower(p);
                else if (_Mode < 1.5) col = Spiral(p);
                else                  col = Sunburst(p);
                return half4(col, 1);
            }
            ENDHLSL
        }
    }
}
