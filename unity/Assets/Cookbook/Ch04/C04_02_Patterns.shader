// 案例 4.2：棋盘格、条纹、波点 —— frac / floor 做重复，smoothstep + fwidth 做抗锯齿。
Shader "Cookbook/Ch04/Patterns"
{
    Properties
    {
        [Enum(Checker,0,Stripes,1,Dots,2)] _Pattern ("Pattern", Float) = 0
        _Scale ("Repeat Count", Float) = 8
        _Angle ("Angle (deg)", Range(-180, 180)) = 0
        _Duty ("Stripe Width / Dot Radius", Range(0.01, 1)) = 0.5
        _ColorA ("Color A", Color) = (0.12, 0.42, 0.56, 1)
        _ColorB ("Color B", Color) = (0.96, 0.93, 0.86, 1)
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
                float _Pattern, _Scale, _Angle, _Duty;
                half4 _ColorA, _ColorB;
            CBUFFER_END

            //#region checker
            float Checker(float2 q)
            {
                // floor 得到格子编号，横纵编号之和的奇偶决定颜色；abs 处理负数格子
                return abs(fmod(floor(q.x) + floor(q.y), 2.0));
            }
            //#endregion

            //#region stripes
            float Stripes(float2 q, float duty)
            {
                // 三角波：在条纹中心为 0、两条纹交界处为 1，宽度用阈值 duty 控制
                float tri = abs(frac(q.x) - 0.5) * 2.0;
                float aa = fwidth(tri);                         // 一个像素内 tri 变化了多少
                return 1.0 - smoothstep(duty - aa, duty + aa, tri);
            }
            //#endregion

            //#region dots
            float Dots(float2 q, float radius)
            {
                // 奇数行错开半格，得到更紧凑的“蜂窝”排布
                float row = floor(q.y);
                q.x += 0.5 * abs(fmod(row, 2.0));
                float2 cell = frac(q) - 0.5;                    // 每格内以中心为原点的局部坐标
                float d = SdCircle(cell, radius * 0.5);
                return FillAA(d);
            }
            //#endregion

            half4 frag (Varyings input) : SV_Target
            {
                // 以面片中心为原点旋转，再放大 _Scale 倍
                float2 q = Rotate2D(input.uv - 0.5, radians(_Angle)) * _Scale;
                float m;
                if (_Pattern < 0.5)      m = Checker(q);
                else if (_Pattern < 1.5) m = Stripes(q, _Duty);
                else                     m = Dots(q, _Duty);
                return half4(lerp(_ColorB.rgb, _ColorA.rgb, m), 1);
            }
            ENDHLSL
        }
    }
}
