// 案例 18.5：全息投影。菲涅尔轮廓 + 世界空间扫描线 + 闪烁 + 故障横移 + 色差（RGB 分离）。
// 透明队列、加法混合、不写深度：全息是“光”，不遮挡后面的东西。（GLSL 版，对应 Ch18/Hologram.shader）
Shader "Cookbook/Ch18/Hologram"
{
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

            GLSLPROGRAM
            #include "Ch18/Ch18Common.glsl"

            uniform vec4  _HoloColor;
            uniform float _BaseAlpha;
            uniform float _RimPower;
            uniform float _ScanDensity;
            uniform float _ScanSpeed;
            uniform float _ScanStrength;
            uniform float _BandWidth;
            uniform float _BandStrength;
            uniform float _FlickerAmount;
            uniform float _GlitchAmount;
            uniform float _GlitchChance;
            uniform float _ChromaShift;
            uniform float _AutoPlay;
            uniform float _Phase;
            uniform vec4  _Toggles;

            VARYING vec3  positionWS;
            VARYING vec3  normalWS;
            VARYING float objectY;     // 物体原点高度，扫描带相对它移动

            float HoloTime() { return _AutoPlay > 0.5 ? _Time.y : _Phase; }

            #ifdef VERTEX
            //#region glitch
            void main()
            {
                vec3 pWS = TransformObjectToWorld(positionOS.xyz);
                float t = HoloTime();
                // 故障：时间按 1/12 秒取整得到“当前这一拍”，这一拍里按概率决定要不要抖
                float beat = floor(t * 12.0);
                float glitchOn = step(1.0 - _GlitchChance, Hash11(beat)) * _Toggles.z;
                // 把物体按高度切成一条条横带，每条带随机左右平移
                float slice = floor(pWS.y * 9.0);
                float shift = (Hash21(vec2(slice, beat)) - 0.5) * 2.0;
                shift *= step(0.7, Hash21(vec2(slice * 1.7, beat + 3.1)));  // 只有部分横带移动
                pWS.x += shift * _GlitchAmount * glitchOn;

                positionWS = pWS;
                gl_Position = TransformWorldToHClip(pWS);
                normalWS = TransformObjectToWorldNormal(normalOS);
                objectY = TransformObjectToWorld(vec3(0.0)).y;
            }
            //#endregion
            #endif

            #ifdef FRAGMENT
            //#region scan
            // 细扫描线：沿世界 Y 的周期条纹。返回 0~1，1 是亮线
            float Scanlines(float y, float t)
            {
                float s = fract(y * _ScanDensity - t * _ScanSpeed);
                return smoothstep(0.25, 0.15, abs(s - 0.5));   // 每个周期中间约 40% 是亮线，边缘柔化防锯齿
            }
            //#endregion

            //#region frag
            void main()
            {
                float t = HoloTime();
                vec3 N = normalize(normalWS);
                vec3 viewWS = GetWorldSpaceNormalizeViewDir(positionWS);

                // 1) 菲涅尔：轮廓亮、正对暗，让中空的“光壳”感出来
                float rim = FresnelRim(N, viewWS, _RimPower);

                // 2) 扫描线 + 一条缓慢上移的宽亮带；色差开启时 R/B 两个通道错开采样
                // 错开量以“一条扫描线周期”为单位：错开整周期就又重合了，0.2~0.35 个周期最明显
                float chroma = _ChromaShift * _Toggles.w;
                float shift = chroma / _ScanDensity;
                vec3 lines = vec3(Scanlines(positionWS.y + shift, t),
                                  Scanlines(positionWS.y,         t),
                                  Scanlines(positionWS.y - shift, t));
                lines = mix(vec3(1.0), lines, _ScanStrength * _Toggles.x);
                float bandPos = fract(t * 0.35) * 2.6 - 0.3;                  // 相对物体原点的高度
                float band = exp(-abs(positionWS.y - objectY - bandPos) / _BandWidth) * _BandStrength * _Toggles.x;

                // 3) 闪烁：每 1/20 秒随机一个亮度，再叠一个快速正弦，模拟电压不稳
                float flick = 0.55 + 0.45 * Hash11(floor(t * 20.0));
                flick *= 0.9 + 0.1 * sin(t * 90.0);
                float flicker = mix(1.0, flick, _FlickerAmount * _Toggles.y);

                // 色差的另一半：R/B 通道的菲涅尔用不同的指数，轮廓处出现彩色镶边
                vec3 rimRGB = vec3(FresnelRim(N, viewWS, _RimPower * (1.0 - chroma)),
                                   rim,
                                   FresnelRim(N, viewWS, _RimPower * (1.0 + chroma)));

                vec3 intensity = (_BaseAlpha + rimRGB) * lines + band;
                vec3 color = _HoloColor.rgb * intensity * flicker;
                fragColor = vec4(color, 1.0);
            }
            //#endregion
            #endif
            ENDGLSL
        }
    }
}
