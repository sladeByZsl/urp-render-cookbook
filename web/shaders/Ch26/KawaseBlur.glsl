// 案例 26.3：Kawase（Pass 0）与 Dual Kawase（Pass 1 下采样 / Pass 2 上采样）。
Shader "Cookbook/Ch26/KawaseBlur"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        ZTest Always ZWrite Off Cull Off

        GLSLINCLUDE
        // _BlitTexture_TexelSize：源纹理（_BlitTexture）的纹素大小，Core.glsl 已声明
        uniform float _KawaseOffset;            // 由 cmd.SetGlobalFloat 逐次设置，不要放进 Properties

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
        vec4 Tap(vec2 uv) { return texture(_BlitTexture, uv); }

        //#region kawase
        // 经典 Kawase：在对角线 4 个点各采一次（每次双线性 = 4 个纹素平均），第 i 次迭代偏移 i+0.5
        vec4 FragKawase()
        {
            vec2 uv = texcoord;
            vec2 d = _BlitTexture_TexelSize.xy * _KawaseOffset;
            vec4 c = Tap(uv + vec2( d.x,  d.y));
            c += Tap(uv + vec2(-d.x,  d.y));
            c += Tap(uv + vec2( d.x, -d.y));
            c += Tap(uv + vec2(-d.x, -d.y));
            return c * 0.25;
        }
        //#endregion

        //#region dual
        // Dual Kawase 下采样：中心权重 4 + 四个对角各 1，共 5 次采样，输出到一半分辨率
        vec4 FragDown()
        {
            vec2 uv = texcoord;
            vec2 h = _BlitTexture_TexelSize.xy * 0.5 * _KawaseOffset;
            vec4 c = Tap(uv) * 4.0;
            c += Tap(uv - h);
            c += Tap(uv + h);
            c += Tap(uv + vec2(h.x, -h.y));
            c += Tap(uv - vec2(h.x, -h.y));
            return c * (1.0 / 8.0);
        }

        // Dual Kawase 上采样：菱形 4 点（权重 1）+ 对角 4 点（权重 2），共 8 次采样，输出到两倍分辨率
        vec4 FragUp()
        {
            vec2 uv = texcoord;
            vec2 h = _BlitTexture_TexelSize.xy * 0.5 * _KawaseOffset;
            vec4 c = Tap(uv + vec2(-h.x * 2.0, 0.0));
            c += Tap(uv + vec2( h.x * 2.0, 0.0));
            c += Tap(uv + vec2(0.0, -h.y * 2.0));
            c += Tap(uv + vec2(0.0,  h.y * 2.0));
            c += Tap(uv + vec2(-h.x,  h.y)) * 2.0;
            c += Tap(uv + vec2( h.x,  h.y)) * 2.0;
            c += Tap(uv + vec2( h.x, -h.y)) * 2.0;
            c += Tap(uv + vec2(-h.x, -h.y)) * 2.0;
            return c * (1.0 / 12.0);
        }
        //#endregion
        #endif
        ENDGLSL

        Pass
        {
            Name "Kawase"
            GLSLPROGRAM
            #ifdef FRAGMENT
            void main() { fragColor = FragKawase(); }
            #endif
            ENDGLSL
        }
        Pass
        {
            Name "DualDown"
            GLSLPROGRAM
            #ifdef FRAGMENT
            void main() { fragColor = FragDown(); }
            #endif
            ENDGLSL
        }
        Pass
        {
            Name "DualUp"
            GLSLPROGRAM
            #ifdef FRAGMENT
            void main() { fragColor = FragUp(); }
            #endif
            ENDGLSL
        }
    }
}
