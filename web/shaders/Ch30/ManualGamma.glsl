// 30.7 节问题现场二（错误示范）：线性空间项目里，自定义后处理又手动做了一次 Gamma 校正。（GLSL 版，对应 Ch30/ManualGamma.shader）
// URP 在线性空间下最终写入 sRGB 目标时会自动编码，这一次 pow(1/2.2) 是多余的，画面整体发灰发白。
Shader "Cookbook/Ch30/ManualGamma"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        ZWrite Off ZTest Always Cull Off Blend Off
        Pass
        {
            Name "ManualGamma"
            GLSLPROGRAM
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
            //#region bug
            void main()
            {
                // 点采样：GLSL 不能按调用选采样器，用 texelFetch
                vec4 c = texelFetch(_BlitTexture, ivec2(texcoord * _BlitTexture_TexelSize.zw), 0);
                c.rgb = pow(max(c.rgb, 0.0), vec3(1.0 / 2.2));   // ✗ 多余：线性 → sRGB 的编码交给管线
                fragColor = c;
            }
            //#endregion
            #endif
            ENDGLSL
        }
    }
}
