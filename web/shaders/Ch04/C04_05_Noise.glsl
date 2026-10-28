// 案例 4.5：从哈希到噪声 —— 白噪声、Value Noise、Gradient Noise、Simplex Noise 并排对比。（GLSL 版）
Shader "Cookbook/Ch04/Noise"
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

            uniform float _Mode, _Scale, _ShowGrid;
            uniform vec4  _Offset;
            uniform vec4  _ColorLow, _ColorHigh;

            #ifdef FRAGMENT
            void main()
            {
                vec2 p = uv * _Scale + _Offset.xy;
                float n;
                //#region select
                if (_Mode < 0.5)      n = Hash21(p);                         // 每格一个随机值，格内不变
                else if (_Mode < 1.5) n = ValueNoise(p);                     // [0,1]
                else if (_Mode < 2.5) n = GradientNoise(p) * 0.5 + 0.5;      // [-1,1] → [0,1]
                else                  n = SimplexNoise(p) * 0.5 + 0.5;
                //#endregion
                vec3 col = mix(_ColorLow.rgb, _ColorHigh.rgb, saturate(n));
                // 叠加整数格线，方便看出“格点”在哪
                vec2 g = abs(fract(p + 0.5) - 0.5) / fwidth(p);
                float line01 = 1.0 - saturate(min(g.x, g.y) - 0.5);
                col = mix(col, vec3(0.91, 0.45, 0.23), line01 * 0.6 * _ShowGrid);
                fragColor = vec4(col, 1.0);
            }
            #endif
            ENDGLSL
        }
    }
}
