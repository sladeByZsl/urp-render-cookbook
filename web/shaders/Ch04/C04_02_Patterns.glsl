// 案例 4.2：棋盘格、条纹、波点 —— frac / floor 做重复，smoothstep + fwidth 做抗锯齿。（GLSL 版）
Shader "Cookbook/Ch04/Patterns"
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

            uniform float _Pattern, _Scale, _Angle, _Duty;
            uniform vec4  _ColorA, _ColorB;

            #ifdef FRAGMENT
            // HLSL 的 fmod：结果与被除数同号（GLSL 的 mod 与除数同号，负数时不同）
            float fmod(float a, float b) { return a - b * trunc(a / b); }

            //#region checker
            float Checker(vec2 q)
            {
                // floor 得到格子编号，横纵编号之和的奇偶决定颜色；abs 处理负数格子
                return abs(fmod(floor(q.x) + floor(q.y), 2.0));
            }
            //#endregion

            //#region stripes
            float Stripes(vec2 q, float duty)
            {
                // 三角波：在条纹中心为 0、两条纹交界处为 1，宽度用阈值 duty 控制
                float tri = abs(fract(q.x) - 0.5) * 2.0;
                float aa = fwidth(tri);                         // 一个像素内 tri 变化了多少
                return 1.0 - smoothstep(duty - aa, duty + aa, tri);
            }
            //#endregion

            //#region dots
            float Dots(vec2 q, float radius)
            {
                // 奇数行错开半格，得到更紧凑的“蜂窝”排布
                float row = floor(q.y);
                q.x += 0.5 * abs(fmod(row, 2.0));
                vec2 cell = fract(q) - 0.5;                     // 每格内以中心为原点的局部坐标
                float d = SdCircle(cell, radius * 0.5);
                return FillAA(d);
            }
            //#endregion

            void main()
            {
                // 以面片中心为原点旋转，再放大 _Scale 倍
                vec2 q = Rotate2D(uv - 0.5, radians(_Angle)) * _Scale;
                float m;
                if (_Pattern < 0.5)      m = Checker(q);
                else if (_Pattern < 1.5) m = Stripes(q, _Duty);
                else                     m = Dots(q, _Duty);
                fragColor = vec4(mix(_ColorB.rgb, _ColorA.rgb, m), 1.0);
            }
            #endif
            ENDGLSL
        }
    }
}
