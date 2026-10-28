// 案例 4.5：从哈希到噪声 —— 白噪声、Value Noise、Gradient Noise、Simplex Noise 并排对比。
Shader "Cookbook/Ch04/Noise"
{
    Properties
    {
        [Enum(Hash,0,Value,1,Gradient,2,Simplex,3)] _Mode ("Noise Type", Float) = 1
        _Scale ("Scale", Float) = 8
        _Offset ("Offset (xy)", Vector) = (0, 0, 0, 0)
        _ColorLow ("Low", Color) = (0.05, 0.08, 0.12, 1)
        _ColorHigh ("High", Color) = (0.95, 0.92, 0.85, 1)
        [Toggle] _ShowGrid ("Show Lattice", Float) = 1
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
                float  _Mode, _Scale, _ShowGrid;
                float4 _Offset;
                half4  _ColorLow, _ColorHigh;
            CBUFFER_END

            half4 frag (Varyings input) : SV_Target
            {
                float2 p = input.uv * _Scale + _Offset.xy;
                float n;
                //#region select
                if (_Mode < 0.5)      n = Hash21(p);                         // 每格一个随机值，格内不变
                else if (_Mode < 1.5) n = ValueNoise(p);                     // [0,1]
                else if (_Mode < 2.5) n = GradientNoise(p) * 0.5 + 0.5;      // [-1,1] → [0,1]
                else                  n = SimplexNoise(p) * 0.5 + 0.5;
                //#endregion
                half3 col = lerp(_ColorLow.rgb, _ColorHigh.rgb, saturate(n));
                // 叠加整数格线，方便看出“格点”在哪
                float2 g = abs(frac(p + 0.5) - 0.5) / fwidth(p);
                float line01 = 1.0 - saturate(min(g.x, g.y) - 0.5);
                col = lerp(col, half3(0.91, 0.45, 0.23), line01 * 0.6 * _ShowGrid);
                return half4(col, 1);
            }
            ENDHLSL
        }
    }
}
