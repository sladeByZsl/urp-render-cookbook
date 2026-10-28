// 案例 25.3：给 URP 自带的 Full Screen Pass Renderer Feature 用的手写 Shader——夜视仪。
// 该 Feature 会把相机颜色拷贝一份，作为 _BlitTexture 传进来，并设置 _BlitScaleBias=(1,1,0,0)，
// 所以直接用 Blit 的全屏三角形顶点着色器即可。
Shader "Cookbook/Ch25/FullscreenNightVision"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        ZTest Always ZWrite Off Cull Off

        Pass
        {
            Name "NightVision"
            GLSLPROGRAM
            uniform float _Gain;
            uniform vec4  _Tint;
            uniform float _ScanlineStrength;
            uniform float _VignetteRadius;

            VARYING vec2 texcoord;
            #ifdef VERTEX
            // Blit.hlsl 的 Vert：全屏三角形
            void main()
            {
                vec2 p = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);
                texcoord = p * _BlitScaleBias.xy + _BlitScaleBias.zw;
                gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
            }
            #endif

            #ifdef FRAGMENT
            float Hash12(vec2 p)
            {
                vec3 p3 = fract(vec3(p.xyx) * 0.1031);
                p3 += dot(p3, p3.yzx + 33.33);
                return fract((p3.x + p3.y) * p3.z);
            }

            //#region frag
            vec4 Frag()
            {
                vec2 uv = texcoord;
                vec3 c = texture(_BlitTexture, uv).rgb;

                // 亮度放大（模拟像增强管），再压一条曲线防止大片死白
                float luma = dot(c, vec3(0.2126, 0.7152, 0.0722)) * _Gain;
                luma = luma / (1.0 + luma);

                // 颗粒噪点：按像素坐标取哈希，_Time 让它在运行时闪动（截图时 _Time≈0）
                vec2 pixel = uv * _ScreenParams.xy;
                float grain = Hash12(pixel + fract(_Time.y * 13.0) * 517.0) - 0.5;
                luma = saturate(luma + grain * 0.12);

                // 扫描线：每 3 像素一条暗线（pixel.y 为正，mod 与 HLSL 的 fmod 结果相同）
                float scan = 1.0 - _ScanlineStrength * step(2.0, mod(pixel.y, 3.0));

                // 圆形镜筒暗角（按宽高比校正成正圆）
                vec2 d = (uv - 0.5) * vec2(_ScreenParams.x / _ScreenParams.y, 1.0);
                float vignette = smoothstep(_VignetteRadius, _VignetteRadius - 0.25, length(d));

                vec3 result = _Tint.rgb * luma * scan * vignette;
                return vec4(result, 1.0);
            }
            //#endregion
            void main() { fragColor = Frag(); }
            #endif
            ENDGLSL
        }
    }
}
