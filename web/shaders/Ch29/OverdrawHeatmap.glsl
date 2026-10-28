// 案例 29.5：把 Overdraw 计数映射成热度图（全屏 Pass，源纹理是计数 RT）。（GLSL 版，对应 Ch29/OverdrawHeatmap.shader）
// 色阶：0 黑 → 1 深蓝 → 2 青 → 3 绿 → 4 黄 → 6 橙 → 8 红 → 12+ 白
Shader "Cookbook/Ch29/OverdrawHeatmap"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        ZWrite Off ZTest Always Cull Off Blend Off
        Pass
        {
            Name "Heatmap"
            GLSLPROGRAM
            uniform float _MaxCount;

            // Blit.hlsl 的 Vert：全屏三角形，_BlitTexture 由引擎提供
            VARYING vec2 texcoord;
            #ifdef VERTEX
            void main()
            {
                vec2 p = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);
                texcoord = p * _BlitScaleBias.xy + _BlitScaleBias.zw;
                gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
            }
            #endif

            #ifdef FRAGMENT
            //#region ramp
            vec3 HeatRamp(float n)
            {
                const vec3 c[8] = vec3[8](
                    vec3(0, 0, 0), vec3(0.05, 0.1, 0.55), vec3(0.0, 0.6, 0.8), vec3(0.1, 0.75, 0.2),
                    vec3(0.95, 0.9, 0.1), vec3(1.0, 0.5, 0.05), vec3(0.9, 0.08, 0.05), vec3(1, 1, 1));
                const float k[8] = float[8](0.0, 1.0, 2.0, 3.0, 4.0, 6.0, 8.0, 12.0);
                n = min(n, k[7] * _MaxCount / 12.0);
                vec3 col = c[7];
                for (int i = 0; i < 7; i++)
                {
                    float a = k[i] * _MaxCount / 12.0, b = k[i + 1] * _MaxCount / 12.0;
                    if (n >= a && n < b) { col = mix(c[i], c[i + 1], (n - a) / (b - a)); break; }
                }
                return col;
            }
            //#endregion

            void main()
            {
                // HLSL 用 sampler_PointClamp 点采样；GLSL 不能按调用选采样器，用 texelFetch 取整数像素
                float count = texelFetch(_BlitTexture, ivec2(texcoord * _BlitTexture_TexelSize.zw), 0).r;
                fragColor = vec4(HeatRamp(count), 1.0);
            }
            #endif
            ENDGLSL
        }
    }
}
