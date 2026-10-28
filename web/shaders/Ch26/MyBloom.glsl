// 案例 26.4：自制 Bloom。Pass 0 预过滤，1 下采样，2 上采样合并，3 合成。
Shader "Cookbook/Ch26/MyBloom"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        ZTest Always ZWrite Off Cull Off

        GLSLINCLUDE
        uniform vec4  _BloomParams;            // x 阈值, y 膝宽, z scatter, w 强度
        uniform vec4  _BloomTint;
        uniform float _BloomDebugView;         // 0 正常, 1 只看预过滤, 2 只看泛光
        uniform sampler2D _BloomLowMip;        // 上采样时的“下一层”（全局纹理）
        uniform sampler2D _BloomTex;           // 合成时的最终泛光（全局纹理）

        VARYING vec2 texcoord;
        #ifdef VERTEX
        // Blit.hlsl 的 Vert：用 gl_VertexID 生成盖住全屏的大三角形（_BlitTexture、_BlitTexture_TexelSize 等在 Core.glsl 里声明）
        void main()
        {
            vec2 p = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);
            texcoord = p * _BlitScaleBias.xy + _BlitScaleBias.zw;
            gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
        }
        #endif

        #ifdef FRAGMENT
        vec3 Tap(vec2 uv) { return texture(_BlitTexture, uv).rgb; }
        float Max3(float a, float b, float c) { return max(max(a, b), c); }

        //#region prefilter
        vec4 FragPrefilter()
        {
            vec2 uv = texcoord;
            vec2 t = _BlitTexture_TexelSize.xy;
            // 4 次双线性 = 4×4 纹素的盒式平均，顺便完成 2 倍降采样
            vec3 c = (Tap(uv + t * vec2(-1, -1)) + Tap(uv + t * vec2(1, -1))
                    + Tap(uv + t * vec2(-1,  1)) + Tap(uv + t * vec2(1,  1))) * 0.25;
            c = min(c, 65000.0);                       // 防止 Inf 一路扩散

            // 软阈值（二次曲线过渡的“膝”）：亮度 b 在 [T-K, T+K] 之间平滑过渡
            float threshold = _BloomParams.x, knee = _BloomParams.y;
            float b = Max3(c.r, c.g, c.b);
            float soft = clamp(b - threshold + knee, 0.0, 2.0 * knee);
            soft = soft * soft / (4.0 * knee + 1e-4);
            float contribution = max(b - threshold, soft) / max(b, 1e-4);
            return vec4(c * contribution, 1.0);
        }
        //#endregion

        //#region down
        // 13 次采样下采样（Jimenez 2014, Next Generation Post Processing in Call of Duty）：
        // 中心 4 点权重 0.5，四个角上的 2×2 小方块各 0.125，能明显抑制高亮像素的闪烁
        vec4 FragDown()
        {
            vec2 uv = texcoord;
            vec2 t = _BlitTexture_TexelSize.xy;
            vec3 A = Tap(uv + t * vec2(-2, -2)), B = Tap(uv + t * vec2(0, -2)), C = Tap(uv + t * vec2(2, -2));
            vec3 D = Tap(uv + t * vec2(-1, -1)), E = Tap(uv + t * vec2(1, -1));
            vec3 F = Tap(uv + t * vec2(-2,  0)), G = Tap(uv),                    H = Tap(uv + t * vec2(2,  0));
            vec3 I = Tap(uv + t * vec2(-1,  1)), J = Tap(uv + t * vec2(1,  1));
            vec3 K = Tap(uv + t * vec2(-2,  2)), L = Tap(uv + t * vec2(0,  2)), M = Tap(uv + t * vec2(2,  2));
            vec3 c = (D + E + I + J) * (0.5 / 4.0);
            c += (A + B + G + F) * (0.125 / 4.0);
            c += (B + C + H + G) * (0.125 / 4.0);
            c += (F + G + L + K) * (0.125 / 4.0);
            c += (G + H + M + L) * (0.125 / 4.0);
            return vec4(c, 1.0);
        }
        //#endregion

        //#region up
        // 上采样：低一层用 3×3 帐篷滤波放大，再与本层按 scatter 插值
        vec4 FragUp()
        {
            vec2 uv = texcoord;
            vec2 t = _BlitTexture_TexelSize.xy;
            #define LOW(o) texture(_BloomLowMip, uv + t * (o)).rgb
            vec3 low = LOW(vec2(-1, -1)) + LOW(vec2(1, -1)) + LOW(vec2(-1, 1)) + LOW(vec2(1, 1));
            low += (LOW(vec2(0, -1)) + LOW(vec2(-1, 0)) + LOW(vec2(1, 0)) + LOW(vec2(0, 1))) * 2.0;
            low += LOW(vec2(0, 0)) * 4.0;
            low *= 1.0 / 16.0;
            #undef LOW
            vec3 high = Tap(uv);
            return vec4(mix(high, low, _BloomParams.z), 1.0);
        }
        //#endregion

        //#region composite
        vec4 FragComposite()
        {
            vec2 uv = texcoord;
            vec4 color = texture(_BlitTexture, uv);
            vec3 bloom = texture(_BloomTex, uv).rgb * _BloomTint.rgb * _BloomParams.w;
            if (_BloomDebugView > 0.5) return vec4(bloom, 1.0);   // 调试：只看泛光
            color.rgb += bloom;                                    // 线性 HDR 空间里直接相加
            return color;
        }
        //#endregion
        #endif
        ENDGLSL

        Pass { Name "Prefilter"
            GLSLPROGRAM
            #ifdef FRAGMENT
            void main() { fragColor = FragPrefilter(); }
            #endif
            ENDGLSL
        }
        Pass { Name "Down"
            GLSLPROGRAM
            #ifdef FRAGMENT
            void main() { fragColor = FragDown(); }
            #endif
            ENDGLSL
        }
        Pass { Name "Up"
            GLSLPROGRAM
            #ifdef FRAGMENT
            void main() { fragColor = FragUp(); }
            #endif
            ENDGLSL
        }
        Pass { Name "Composite"
            GLSLPROGRAM
            #ifdef FRAGMENT
            void main() { fragColor = FragComposite(); }
            #endif
            ENDGLSL
        }
    }
}
