// 案例 18.5：全息投影。菲涅尔轮廓 + 世界空间扫描线 + 闪烁 + 故障横移 + 色差（RGB 分离）。
// 透明队列、加法混合、不写深度：全息是“光”，不遮挡后面的东西。
Shader "Cookbook/Ch18/Hologram"
{
    Properties
    {
        [HDR] _HoloColor ("Holo Color", Color) = (0.25,1.1,2.2,1)
        _BaseAlpha ("Base Alpha", Range(0,1)) = 0.12
        _RimPower ("Rim Power", Range(0.5,8)) = 2.2
        [Header(Scanlines)]
        _ScanDensity ("Scanline Density (per meter)", Float) = 60
        _ScanSpeed ("Scanline Speed", Float) = 1.5
        _ScanStrength ("Scanline Strength", Range(0,1)) = 0.6
        _BandWidth ("Scan Band Width", Range(0.01,1)) = 0.25
        _BandStrength ("Scan Band Strength", Range(0,4)) = 1.2
        [Header(Flicker and Glitch)]
        _FlickerAmount ("Flicker Amount", Range(0,1)) = 0.3
        _GlitchAmount ("Glitch Offset (m)", Range(0,0.3)) = 0.06
        _GlitchChance ("Glitch Chance", Range(0,1)) = 0.3
        [Header(Chromatic)]
        _ChromaShift ("RGB Shift (fraction of a scanline)", Range(0,0.5)) = 0.2
        [Header(Time)]
        [Toggle] _AutoPlay ("Auto Play (_Time)", Float) = 0
        _Phase ("Phase (seconds, for screenshots)", Float) = 0
        _Toggles ("Feature Toggles (scan, flicker, glitch, chroma)", Vector) = (1,1,1,1)
    }

    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent" "RenderPipeline"="UniversalPipeline" }

        Pass
        {
            Name "Hologram"
            Tags { "LightMode"="UniversalForward" }
            Blend One One           // 加法：越叠越亮，背景不会被盖住
            ZWrite Off
            Cull Back

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Assets/Cookbook/Ch18/Ch18Common.hlsl"

            CBUFFER_START(UnityPerMaterial)
                half4 _HoloColor;
                half  _BaseAlpha;
                half  _RimPower;
                float _ScanDensity;
                float _ScanSpeed;
                half  _ScanStrength;
                half  _BandWidth;
                half  _BandStrength;
                half  _FlickerAmount;
                half  _GlitchAmount;
                half  _GlitchChance;
                half  _ChromaShift;
                half  _AutoPlay;
                float _Phase;
                half4 _Toggles;
            CBUFFER_END

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; };
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                half3  normalWS   : TEXCOORD1;
                float  objectY    : TEXCOORD2;   // 物体原点高度，扫描带相对它移动
            };

            float HoloTime() { return _AutoPlay > 0.5 ? _Time.y : _Phase; }

            //#region glitch
            Varyings vert(Attributes v)
            {
                Varyings o;
                float3 positionWS = TransformObjectToWorld(v.positionOS.xyz);
                float t = HoloTime();
                // 故障：时间按 1/12 秒取整得到“当前这一拍”，这一拍里按概率决定要不要抖
                float beat = floor(t * 12.0);
                float glitchOn = step(1.0 - _GlitchChance, Hash11(beat)) * _Toggles.z;
                // 把物体按高度切成一条条横带，每条带随机左右平移
                float slice = floor(positionWS.y * 9.0);
                float shift = (Hash21(float2(slice, beat)) - 0.5) * 2.0;
                shift *= step(0.7, Hash21(float2(slice * 1.7, beat + 3.1)));  // 只有部分横带移动
                positionWS.x += shift * _GlitchAmount * glitchOn;

                o.positionWS = positionWS;
                o.positionCS = TransformWorldToHClip(positionWS);
                o.normalWS = TransformObjectToWorldNormal(v.normalOS);
                o.objectY = TransformObjectToWorld(float3(0, 0, 0)).y;
                return o;
            }
            //#endregion

            //#region scan
            // 细扫描线：沿世界 Y 的周期条纹。返回 0~1，1 是亮线
            half Scanlines(float y, float t)
            {
                float s = frac(y * _ScanDensity - t * _ScanSpeed);
                return smoothstep(0.25, 0.15, abs(s - 0.5));   // 每个周期中间约 40% 是亮线，边缘柔化防锯齿
            }
            //#endregion

            //#region frag
            half4 frag(Varyings i) : SV_Target
            {
                float t = HoloTime();
                half3 normalWS = normalize(i.normalWS);
                half3 viewWS = GetWorldSpaceNormalizeViewDir(i.positionWS);

                // 1) 菲涅尔：轮廓亮、正对暗，让中空的“光壳”感出来
                half rim = FresnelRim(normalWS, viewWS, _RimPower);

                // 2) 扫描线 + 一条缓慢上移的宽亮带；色差开启时 R/B 两个通道错开采样
                // 错开量以“一条扫描线周期”为单位：错开整周期就又重合了，0.2~0.35 个周期最明显
                half chroma = _ChromaShift * _Toggles.w;
                float shift = chroma / _ScanDensity;
                half3 lines = half3(Scanlines(i.positionWS.y + shift, t),
                                    Scanlines(i.positionWS.y,         t),
                                    Scanlines(i.positionWS.y - shift, t));
                lines = lerp(1.0h, lines, _ScanStrength * _Toggles.x);
                float bandPos = frac(t * 0.35) * 2.6 - 0.3;                  // 相对物体原点的高度
                half band = exp(-abs(i.positionWS.y - i.objectY - bandPos) / _BandWidth) * _BandStrength * _Toggles.x;

                // 3) 闪烁：每 1/20 秒随机一个亮度，再叠一个快速正弦，模拟电压不稳
                float flick = 0.55 + 0.45 * Hash11(floor(t * 20.0));
                flick *= 0.9 + 0.1 * sin(t * 90.0);
                half flicker = lerp(1.0h, flick, _FlickerAmount * _Toggles.y);

                // 色差的另一半：R/B 通道的菲涅尔用不同的指数，轮廓处出现彩色镶边
                half3 rimRGB = half3(FresnelRim(normalWS, viewWS, _RimPower * (1.0h - chroma)),
                                     rim,
                                     FresnelRim(normalWS, viewWS, _RimPower * (1.0h + chroma)));

                half3 intensity = (_BaseAlpha + rimRGB) * lines + band;
                half3 color = _HoloColor.rgb * intensity * flicker;
                return half4(color, 1);
            }
            //#endregion
            ENDHLSL
        }
    }
}
