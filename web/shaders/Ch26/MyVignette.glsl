// 案例 26.6：暗角。以 center 为圆心，半径越大越接近 _VignetteColor。
Shader "Cookbook/Ch26/MyVignette"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        ZTest Always ZWrite Off Cull Off
        Pass
        {
            Name "Vignette"
            GLSLPROGRAM
            uniform vec4  _VignetteColor;
            uniform vec4  _VignetteParams;   // xy 中心, z 强度, w 柔和度
            uniform float _VignetteRounded;

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
                vec2 uv = texcoord;
                vec4 color = texture(_BlitTexture, uv);

                vec2 d = (uv - _VignetteParams.xy) * 2.0;                 // 屏幕边缘中点处 |d| = 1
                d.x *= mix(1.0, _ScreenParams.x / _ScreenParams.y, _VignetteRounded);
                float r = length(d);

                // 强度决定暗角从哪里开始，柔和度决定过渡带宽度
                float inner = 1.3 - _VignetteParams.z;
                float mask = smoothstep(inner, inner + _VignetteParams.w, r);
                color.rgb = mix(color.rgb, _VignetteColor.rgb, mask);
                return color;
            }
            //#endregion
            void main() { fragColor = Frag(); }
            #endif
            ENDGLSL
        }
    }
}
