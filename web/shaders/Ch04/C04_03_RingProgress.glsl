// 案例 4.3（上）：圆环进度条 —— 极坐标判断“走到哪了”，SDF 画圆头。（GLSL 版）
Shader "Cookbook/Ch04/RingProgress"
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

            uniform float _Progress, _Radius, _Thickness;
            uniform vec4  _ColorStart, _ColorEnd, _TrackColor, _BgColor, _GlowColor;

            #ifdef FRAGMENT
            void main()
            {
                vec2 p = uv * 2.0 - 1.0;                         // [-1,1]，中心为原点
                //#region arc
                float r = length(p);
                // 从 12 点方向开始、顺时针增加的角度，归一化到 [0,1)
                float a01 = fract(atan(p.x, p.y) / TWO_PI + 1.0);
                float hw = _Thickness * 0.5;

                float ring = abs(r - _Radius) - hw;              // 整圈环带的 SDF
                // 已走过的部分：角度在进度内就用环带距离，否则用到两个“圆头”的距离
                float endAngle = _Progress * TWO_PI;
                vec2 capStart = vec2(0.0, _Radius);
                vec2 capEnd   = _Radius * vec2(sin(endAngle), cos(endAngle));
                float caps = min(length(p - capStart), length(p - capEnd)) - hw;
                float arc = (a01 <= _Progress) ? ring : caps;
                if (_Progress <= 0.0) arc = 1.0;                  // 进度为 0 时什么都不画
                //#endregion

                vec3 col = _BgColor.rgb;
                col = mix(col, _TrackColor.rgb, FillAA(ring));   // 底部轨道
                // 外发光：距离越远越暗的指数衰减
                col += _GlowColor.rgb * exp(-max(arc, 0.0) * 30.0) * 0.6;
                // 沿弧长渐变；圆头部分按离哪个头近取首/尾颜色
                float t = (a01 <= _Progress) ? a01 / max(_Progress, 1e-4)
                                             : (length(p - capStart) < length(p - capEnd) ? 0.0 : 1.0);
                vec3 fillCol = mix(_ColorStart.rgb, _ColorEnd.rgb, t);
                col = mix(col, fillCol, FillAA(arc));
                fragColor = vec4(col, 1.0);
            }
            #endif
            ENDGLSL
        }
    }
}
