// 全屏拷贝（URP Blit.shader）与最终输出到画布（线性 → sRGB）
Shader "Hidden/Cookbook/Blit"
{
    SubShader
    {
        ZTest Always ZWrite Off Cull Off
        GLSLINCLUDE
        VARYING vec2 uv;
        #ifdef VERTEX
        void main()
        {
            vec2 p = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);
            uv = p * _BlitScaleBias.xy + _BlitScaleBias.zw;
            gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
        }
        #endif
        ENDGLSL

        Pass
        {
            Name "Copy"
            GLSLPROGRAM
            #ifdef FRAGMENT
            void main() { fragColor = textureLod(_BlitTexture, uv, _BlitMipLevel); }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "FinalBlit"
            GLSLPROGRAM
            uniform float _OutputSRGB;
            #ifdef FRAGMENT
            void main()
            {
                vec4 c = texture(_BlitTexture, uv);
                c.rgb = saturate(c.rgb);
                if (_OutputSRGB > 0.5) c.rgb = LinearToSRGB(c.rgb);
                fragColor = vec4(c.rgb, 1.0);
            }
            #endif
            ENDGLSL
        }
    }
}
