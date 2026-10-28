// 案例 4.3（下）：分段血条 —— 圆角矩形 SDF、受伤拖尾、低血量闪烁。
Shader "Cookbook/Ch04/HealthBar"
{
    Properties
    {
        _Health ("Health", Range(0, 1)) = 0.6
        _Trail ("Damage Trail", Range(0, 1)) = 0.75
        _Segments ("Segments", Float) = 10
        _Aspect ("Quad Aspect (w/h)", Float) = 6
        _ColorFull ("Color Full", Color) = (0.30, 0.80, 0.35, 1)
        _ColorLow ("Color Low", Color) = (0.90, 0.20, 0.15, 1)
        _TrailColor ("Trail Color", Color) = (1.0, 0.85, 0.55, 1)
        _FrameColor ("Frame", Color) = (0.05, 0.06, 0.07, 1)
        _EmptyColor ("Empty", Color) = (0.18, 0.20, 0.22, 1)
        _BgColor ("Background", Color) = (0.08, 0.10, 0.12, 1)
        _LowThreshold ("Low Health Threshold", Range(0, 1)) = 0.3
        _FlashSpeed ("Flash Speed", Float) = 8
        _FlashPhase ("Flash Phase (for stills)", Float) = 0
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
                float _Health, _Trail, _Segments, _Aspect, _LowThreshold, _FlashSpeed, _FlashPhase;
                half4 _ColorFull, _ColorLow, _TrailColor, _FrameColor, _EmptyColor, _BgColor;
            CBUFFER_END

            half4 frag (Varyings input) : SV_Target
            {
                //#region layout
                // 乘以宽高比，让 SDF 在拉长的面片上仍然是“正”的（圆角不会被压扁）
                float2 p = (input.uv - 0.5) * float2(_Aspect, 1.0);
                float2 halfSize = float2(_Aspect * 0.5, 0.5);
                float outer = SdRoundBox(p, halfSize - 0.04, 0.22);     // 外框
                float inner = SdRoundBox(p, halfSize - 0.14, 0.13);     // 槽
                // 槽内的横向进度 0..1
                float innerHalfW = halfSize.x - 0.14;
                float x01 = saturate((p.x + innerHalfW) / (2.0 * innerHalfW));
                //#endregion

                //#region fill
                // 血量颜色：低于阈值后快速变红
                half3 hpCol = lerp(_ColorLow.rgb, _ColorFull.rgb, smoothstep(_LowThreshold * 0.6, _LowThreshold * 1.6, _Health));
                // 低血量闪烁：_Time 驱动；静帧时用 _FlashPhase
                float flash = 0.5 + 0.5 * sin(_Time.y * _FlashSpeed + _FlashPhase);
                hpCol *= (_Health < _LowThreshold) ? lerp(0.7, 1.4, flash) : 1.0;

                float px = fwidth(x01);
                float hpMask    = 1.0 - smoothstep(_Health - px, _Health + px, x01);
                float trailMask = 1.0 - smoothstep(_Trail  - px, _Trail  + px, x01);

                half3 col = _EmptyColor.rgb;
                col = lerp(col, _TrailColor.rgb, trailMask);           // 先画拖尾，再盖上当前血量
                col = lerp(col, hpCol, hpMask);
                // 上亮下暗，做出一点体积感
                col *= lerp(0.75, 1.15, smoothstep(-0.35, 0.35, p.y));
                // 分段刻度：frac 重复出竖线
                float seg = abs(frac(x01 * _Segments + 0.5) - 0.5) / _Segments;   // 到最近刻度的距离（x01 单位）
                col *= lerp(0.55, 1.0, smoothstep(px * 0.5, px * 1.5, seg));
                //#endregion

                half3 outCol = lerp(_BgColor.rgb, _FrameColor.rgb, FillAA(outer));
                outCol = lerp(outCol, col, FillAA(inner));
                return half4(outCol, 1);
            }
            ENDHLSL
        }
    }
}
