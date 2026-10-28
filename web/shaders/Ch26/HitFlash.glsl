// 案例 26.10：受击红屏——屏幕边缘的血色晕染 + 噪声“血丝” + 整体轻微压暗去色。
Shader "Cookbook/Ch26/HitFlash"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        ZTest Always ZWrite Off Cull Off
        Pass
        {
            Name "HitFlash"
            GLSLPROGRAM
            uniform vec4 _HitColor;
            uniform vec4 _HitParams;   // x 强度, y 噪声尺度, z 相位

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
            float Hash21(vec2 p)
            {
                p = fract(p * vec2(123.34, 456.21));
                p += dot(p, p + 45.32);
                return fract(p.x * p.y);
            }
            float ValueNoise(vec2 p)
            {
                vec2 i = floor(p), f = fract(p);
                vec2 u = f * f * (3.0 - 2.0 * f);
                return mix(mix(Hash21(i), Hash21(i + vec2(1, 0)), u.x),
                           mix(Hash21(i + vec2(0, 1)), Hash21(i + vec2(1, 1)), u.x), u.y);
            }
            float Fbm(vec2 p)
            {
                float s = 0.0, a = 0.5;
                for (int k = 0; k < 4; k++) { s += a * ValueNoise(p); p *= 2.03; a *= 0.5; }
                return s;
            }

            //#region frag
            vec4 Frag()
            {
                vec2 uv = texcoord;
                vec4 color = texture(_BlitTexture, uv);
                float k = _HitParams.x;

                // 1) 椭圆形的边缘遮罩：强度越大，红色往中心侵入越深
                vec2 d = (uv - 0.5) * 2.0;
                float r = length(d * vec2(1.0, 0.85));

                // 2) 用 fBm 噪声扰动遮罩边界，形成不规则的“血丝”；相位让它在运行时蠕动
                float t = _HitParams.z + _Time.y * 0.6;
                float n = Fbm(uv * _HitParams.y + vec2(t, -t * 0.7));
                float inner = mix(1.25, 0.45, k);
                float edge = smoothstep(inner, inner + 0.55, r + (n - 0.5) * 0.45);

                // 3) 中心区域轻微去色、压暗，模拟“眼前一黑”
                float luma = dot(color.rgb, vec3(0.2126, 0.7152, 0.0722));
                vec3 dimmed = mix(color.rgb, vec3(luma) * vec3(1.0, 0.85, 0.85), 0.35 * k) * (1.0 - 0.2 * k);

                // 4) 边缘：用乘 + 加的组合，暗部也能被染红，亮部不会变成纯色块
                vec3 blood = dimmed * _HitColor.rgb * 0.6 + _HitColor.rgb * 0.35;
                color.rgb = mix(dimmed, blood, edge * saturate(k * 1.5));
                return color;
            }
            //#endregion
            void main() { fragColor = Frag(); }
            #endif
            ENDGLSL
        }
    }
}
