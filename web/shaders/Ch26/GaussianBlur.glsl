// 案例 26.2：可分离高斯。9 个权重的一维高斯核，借助双线性过滤只需 5 次采样。
Shader "Cookbook/Ch26/GaussianBlur"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        ZTest Always ZWrite Off Cull Off

        GLSLINCLUDE
        // _BlitTexture_TexelSize 由 Core.glsl 声明，引擎绑定纹理时自动填写
        uniform float _Spread;

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
        //#region blur
        // 9 抽头核 [66 220 495 792 924 792 495 220 66]/4070（二项式第 12 行去掉最外两对后归一化，
        // 与 URP Bloom.shader 用的是同一组权重）。相邻两项合并成一次双线性采样：
        // 偏移 0, 1.3846, 3.2308（纹素），权重 0.2270, 0.3162, 0.0703 —— 9 个权重只要 5 次采样
        vec4 Blur1D(vec2 uv, vec2 dir)
        {
            const float o1 = 1.3846153846, o2 = 3.2307692308;
            const float w0 = 0.2270270270, w1 = 0.3162162162, w2 = 0.0702702703;
            vec2 du = dir * _BlitTexture_TexelSize.xy * _Spread;
            vec4 c = texture(_BlitTexture, uv) * w0;
            c += texture(_BlitTexture, uv + du * o1) * w1;
            c += texture(_BlitTexture, uv - du * o1) * w1;
            c += texture(_BlitTexture, uv + du * o2) * w2;
            c += texture(_BlitTexture, uv - du * o2) * w2;
            return c;
        }
        //#endregion
        #endif
        ENDGLSL

        Pass
        {
            Name "BlurH"
            GLSLPROGRAM
            #ifdef FRAGMENT
            void main() { fragColor = Blur1D(texcoord, vec2(1, 0)); }
            #endif
            ENDGLSL
        }
        Pass
        {
            Name "BlurV"
            GLSLPROGRAM
            #ifdef FRAGMENT
            void main() { fragColor = Blur1D(texcoord, vec2(0, 1)); }
            #endif
            ENDGLSL
        }
    }
}
