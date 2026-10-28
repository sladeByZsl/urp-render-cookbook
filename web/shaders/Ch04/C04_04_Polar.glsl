// 案例 4.4：极坐标图案 —— 花瓣、螺旋、旋转的放射光。（GLSL 版）
Shader "Cookbook/Ch04/Polar"
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

            uniform float _Mode, _Count, _Twist, _Angle, _Speed;
            uniform vec4  _ColorA, _ColorB, _BgColor;

            #ifdef FRAGMENT
            //#region flower
            vec3 Flower(vec2 p)
            {
                vec2 pol = ToPolar(p);
                float theta = pol.y * TWO_PI;
                // 半径随角度起伏：r(θ) = 基础半径 + 振幅·cos(Nθ)，N 片花瓣
                float edge = 0.55 + 0.25 * cos(_Count * theta);
                float petal = FillAA(pol.x - edge);
                // 花瓣内部再按半径做一层渐变，中心是一颗小圆
                vec3 col = mix(_BgColor.rgb, mix(_ColorA.rgb, _ColorA.rgb * 0.55, pol.x / edge), petal);
                col = mix(col, _ColorB.rgb, FillAA(SdCircle(p, 0.2)));
                return col;
            }
            //#endregion

            //#region spiral
            vec3 Spiral(vec2 p)
            {
                vec2 pol = ToPolar(p);
                // 角度 + log(半径)：沿径向每走 e 倍，条纹转过 _Twist 圈 → 对数螺线
                float s = fract(pol.y * _Count + log(max(pol.x, 1e-4)) * _Twist);
                float band = abs(s - 0.5) * 2.0;
                float aa = fwidth(band);
                float m = smoothstep(0.5 - aa, 0.5 + aa, band);
                vec3 col = mix(_ColorA.rgb, _ColorB.rgb, m);
                // 中心处条纹无限变细，必然出摩尔纹；用一个圆盖住
                return mix(col, _BgColor.rgb, FillAA(SdCircle(p, 0.06)));
            }
            //#endregion

            //#region sunburst
            vec3 Sunburst(vec2 p)
            {
                vec2 pol = ToPolar(p);
                float t = pol.y * _Count;                  // 每条光芒占 1 个单位
                float tri = abs(fract(t) - 0.5) * 2.0;
                // 坑：pol.y 在 +X 轴处从 1 跳回 0，fwidth 会在那条线上暴涨，画出一道“裂缝”。
                // 解决：用另一个在别处断开的角度（偏移半圈）求导，两者取小。
                float a2 = fract(pol.y + 0.5) * _Count;
                float aa = min(fwidth(t), fwidth(a2)) * 2.0;
                float ray = smoothstep(0.5 - aa, 0.5 + aa, tri);
                vec3 col = mix(_ColorA.rgb, _ColorB.rgb, ray);
                // 向外渐暗 + 中心太阳
                col *= mix(1.15, 0.55, saturate(pol.x));
                return mix(col, vec3(1.0, 0.85, 0.45), FillAA(SdCircle(p, 0.22)));
            }
            //#endregion

            void main()
            {
                vec2 p = (uv - 0.5) * 2.0;
                // 旋转矩阵：静态角度 + 随时间转动（截图时 _Time≈0，只用 _Angle）
                p = Rotate2D(p, radians(_Angle + _Speed * _Time.y));
                vec3 col;
                if (_Mode < 0.5)      col = Flower(p);
                else if (_Mode < 1.5) col = Spiral(p);
                else                  col = Sunburst(p);
                fragColor = vec4(col, 1.0);
            }
            #endif
            ENDGLSL
        }
    }
}
