// 案例 26.6：色差。沿径向把 R、G、B 采样到不同位置；采样数 > 3 时用“光谱权重”做平滑色散。
Shader "Cookbook/Ch26/MyChromaticAberration"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        ZTest Always ZWrite Off Cull Off
        Pass
        {
            Name "ChromaticAberration"
            GLSLPROGRAM
            uniform vec4 _CAParams;   // x 强度, y 采样数

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
            // t ∈ [0,1] 映射到 红→绿→蓝 的权重（三段帐篷函数），所有样本的权重之和按通道归一化
            vec3 SpectrumWeight(float t)
            {
                float r = saturate(1.0 - abs(t * 2.0));
                float g = saturate(1.0 - abs(t * 2.0 - 1.0));
                float b = saturate(1.0 - abs(t * 2.0 - 2.0));
                return vec3(r, g, b);
            }

            //#region frag
            vec4 Frag()
            {
                vec2 uv = texcoord;
                vec2 d = uv - 0.5;
                // 偏移随半径平方增长：中心几乎无色差，边缘最强（和真实镜头的横向色差一致）
                vec2 offset = d * dot(d, d) * _CAParams.x * 0.15;

                int n = int(_CAParams.y);
                vec3 sum = vec3(0.0), wsum = vec3(0.0);
                for (int i = 0; i < n; i++)
                {
                    float t = float(i) / float(n - 1);         // 0 = 红（向外）… 1 = 蓝（向内）
                    vec3 w = SpectrumWeight(t);
                    vec2 suv = uv + offset * (0.5 - t) * 2.0;
                    sum += texture(_BlitTexture, suv).rgb * w;
                    wsum += w;
                }
                return vec4(sum / max(wsum, vec3(1e-4)), 1.0);
            }
            //#endregion
            void main() { fragColor = Frag(); }
            #endif
            ENDGLSL
        }
    }
}
