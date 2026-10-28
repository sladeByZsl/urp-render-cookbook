// 案例 26.1：饱和度 / 对比度。
Shader "Cookbook/Ch26/Saturation"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        ZTest Always ZWrite Off Cull Off

        Pass
        {
            Name "Saturation"
            GLSLPROGRAM
            uniform float _Saturation;
            uniform float _Contrast;

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
            //#region frag
            vec4 Frag()
            {
                vec4 color = texture(_BlitTexture, texcoord);

                // 饱和度：在“原色”与“同亮度的灰”之间插值，>1 时外插 = 更鲜艳
                float luma = dot(color.rgb, vec3(0.2126, 0.7152, 0.0722));
                color.rgb = mix(vec3(luma), color.rgb, _Saturation);

                // 对比度：在 log2 空间以中灰为支点缩放，HDR 亮部不会被直接截断
                const float midGrey = 0.18;
                vec3 logC = log2(max(color.rgb, 1e-5) / midGrey);
                color.rgb = midGrey * exp2(logC * _Contrast);
                return color;
            }
            //#endregion
            void main() { fragColor = Frag(); }
            #endif
            ENDGLSL
        }
    }
}
