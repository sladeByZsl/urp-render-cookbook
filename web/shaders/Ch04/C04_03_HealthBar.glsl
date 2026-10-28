// 案例 4.3（下）：分段血条 —— 圆角矩形 SDF、受伤拖尾、低血量闪烁。（GLSL 版）
Shader "Cookbook/Ch04/HealthBar"
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

            uniform float _Health, _Trail, _Segments, _Aspect, _LowThreshold, _FlashSpeed, _FlashPhase;
            uniform vec4  _ColorFull, _ColorLow, _TrailColor, _FrameColor, _EmptyColor, _BgColor;

            #ifdef FRAGMENT
            void main()
            {
                //#region layout
                // 乘以宽高比，让 SDF 在拉长的面片上仍然是“正”的（圆角不会被压扁）
                vec2 p = (uv - 0.5) * vec2(_Aspect, 1.0);
                vec2 halfSize = vec2(_Aspect * 0.5, 0.5);
                float outer = SdRoundBox(p, halfSize - 0.04, 0.22);     // 外框
                float inner = SdRoundBox(p, halfSize - 0.14, 0.13);     // 槽
                // 槽内的横向进度 0..1
                float innerHalfW = halfSize.x - 0.14;
                float x01 = saturate((p.x + innerHalfW) / (2.0 * innerHalfW));
                //#endregion

                //#region fill
                // 血量颜色：低于阈值后快速变红
                vec3 hpCol = mix(_ColorLow.rgb, _ColorFull.rgb, smoothstep(_LowThreshold * 0.6, _LowThreshold * 1.6, _Health));
                // 低血量闪烁：_Time 驱动；静帧时用 _FlashPhase
                float flash = 0.5 + 0.5 * sin(_Time.y * _FlashSpeed + _FlashPhase);
                hpCol *= (_Health < _LowThreshold) ? mix(0.7, 1.4, flash) : 1.0;

                float px = fwidth(x01);
                float hpMask    = 1.0 - smoothstep(_Health - px, _Health + px, x01);
                float trailMask = 1.0 - smoothstep(_Trail  - px, _Trail  + px, x01);

                vec3 col = _EmptyColor.rgb;
                col = mix(col, _TrailColor.rgb, trailMask);            // 先画拖尾，再盖上当前血量
                col = mix(col, hpCol, hpMask);
                // 上亮下暗，做出一点体积感
                col *= mix(0.75, 1.15, smoothstep(-0.35, 0.35, p.y));
                // 分段刻度：fract 重复出竖线
                float seg = abs(fract(x01 * _Segments + 0.5) - 0.5) / _Segments;   // 到最近刻度的距离（x01 单位）
                col *= mix(0.55, 1.0, smoothstep(px * 0.5, px * 1.5, seg));
                //#endregion

                vec3 outCol = mix(_BgColor.rgb, _FrameColor.rgb, FillAA(outer));
                outCol = mix(outCol, col, FillAA(inner));
                fragColor = vec4(outCol, 1.0);
            }
            #endif
            ENDGLSL
        }
    }
}
