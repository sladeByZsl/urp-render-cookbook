// 案例 4.8：域扭曲（Domain Warping）—— 用噪声去扭曲另一个噪声的输入坐标。
Shader "Cookbook/Ch04/DomainWarp"
{
    Properties
    {
        [IntRange] _Levels ("Warp Levels", Range(0, 2)) = 2
        _Scale ("Scale", Float) = 3
        _Strength ("Warp Strength", Float) = 4
        [IntRange] _Octaves ("Octaves", Range(1, 8)) = 5
        _Offset ("Offset (for stills)", Vector) = (0, 0, 0, 0)
        _Speed ("Flow Speed", Float) = 0.1
        _Color1 ("Color 1", Color) = (0.10, 0.20, 0.30, 1)
        _Color2 ("Color 2", Color) = (0.85, 0.55, 0.30, 1)
        _Color3 ("Color 3", Color) = (0.95, 0.92, 0.82, 1)
        _Color4 ("Color 4", Color) = (0.15, 0.45, 0.55, 1)
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
                float  _Levels, _Scale, _Strength, _Octaves, _Speed;
                float4 _Offset;
                half4  _Color1, _Color2, _Color3, _Color4;
            CBUFFER_END

            float F(float2 p) { return Fbm(p, (int)_Octaves, 2.0, 0.5); }   // 约 [-1,1]

            half4 frag (Varyings input) : SV_Target
            {
                float2 p = input.uv * _Scale + _Offset.xy;
                float t = _Time.y * _Speed;
                //#region warp
                // 第 1 层：q 是一个二维“位移场”，两个分量用两个不同偏移的 fBm
                float2 q = 0;
                if (_Levels >= 1)
                    q = float2(F(p + float2(0.0, 0.0) + t), F(p + float2(5.2, 1.3) - t));
                // 第 2 层：拿被 q 扭过的坐标再求一次位移场 r
                float2 r = 0;
                if (_Levels >= 2)
                    r = float2(F(p + _Strength * q + float2(1.7, 9.2)), F(p + _Strength * q + float2(8.3, 2.8)));
                // 最终：在被扭曲的坐标上采样
                float2 warped = p + _Strength * ((_Levels >= 2) ? r : q);
                float f = F(warped) * 0.5 + 0.5;
                //#endregion

                //#region color
                // 用 f、|q|、r.x 三个量混色：位移场本身也是很好的“着色依据”
                half3 col = lerp(_Color1.rgb, _Color2.rgb, saturate(f * f * 2.2));
                col = lerp(col, _Color4.rgb, saturate(length(q) * 0.9));
                col = lerp(col, _Color3.rgb, saturate(abs(r.x) * 1.2) * step(1.5, _Levels));
                col *= 0.6 + 0.6 * f;
                //#endregion
                return half4(col, 1);
            }
            ENDHLSL
        }
    }
}
