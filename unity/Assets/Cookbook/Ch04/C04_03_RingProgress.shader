// 案例 4.3（上）：圆环进度条 —— 极坐标判断“走到哪了”，SDF 画圆头。
Shader "Cookbook/Ch04/RingProgress"
{
    Properties
    {
        _Progress ("Progress", Range(0, 1)) = 0.65
        _Radius ("Radius", Range(0.1, 0.9)) = 0.62
        _Thickness ("Thickness", Range(0.01, 0.5)) = 0.16
        _ColorStart ("Color Start", Color) = (0.12, 0.62, 0.86, 1)
        _ColorEnd ("Color End", Color) = (0.91, 0.45, 0.23, 1)
        _TrackColor ("Track Color", Color) = (0.22, 0.26, 0.30, 1)
        _BgColor ("Background", Color) = (0.08, 0.10, 0.12, 1)
        [HDR] _GlowColor ("Glow", Color) = (0.6, 0.35, 0.15, 1)
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
                float _Progress, _Radius, _Thickness;
                half4 _ColorStart, _ColorEnd, _TrackColor, _BgColor, _GlowColor;
            CBUFFER_END

            half4 frag (Varyings input) : SV_Target
            {
                float2 p = input.uv * 2.0 - 1.0;                 // [-1,1]，中心为原点
                //#region arc
                float r = length(p);
                // 从 12 点方向开始、顺时针增加的角度，归一化到 [0,1)
                float a01 = frac(atan2(p.x, p.y) / TWO_PI + 1.0);
                float hw = _Thickness * 0.5;

                float ring = abs(r - _Radius) - hw;              // 整圈环带的 SDF
                // 已走过的部分：角度在进度内就用环带距离，否则用到两个“圆头”的距离
                float endAngle = _Progress * TWO_PI;
                float2 capStart = float2(0.0, _Radius);
                float2 capEnd   = _Radius * float2(sin(endAngle), cos(endAngle));
                float caps = min(length(p - capStart), length(p - capEnd)) - hw;
                float arc = (a01 <= _Progress) ? ring : caps;
                if (_Progress <= 0.0) arc = 1.0;                  // 进度为 0 时什么都不画
                //#endregion

                half3 col = _BgColor.rgb;
                col = lerp(col, _TrackColor.rgb, FillAA(ring));  // 底部轨道
                // 外发光：距离越远越暗的指数衰减
                col += _GlowColor.rgb * exp(-max(arc, 0.0) * 30.0) * 0.6;
                // 沿弧长渐变；圆头部分按离哪个头近取首/尾颜色
                float t = (a01 <= _Progress) ? a01 / max(_Progress, 1e-4)
                                             : (length(p - capStart) < length(p - capEnd) ? 0.0 : 1.0);
                half3 fillCol = lerp(_ColorStart.rgb, _ColorEnd.rgb, t);
                col = lerp(col, fillCol, FillAA(arc));
                return half4(col, 1);
            }
            ENDHLSL
        }
    }
}
