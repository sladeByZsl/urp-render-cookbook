// URP 的 Stop NaN（相机 Stop NaNs 选项，StopNaN.shader）：后处理开始前把 NaN / Inf 像素换成黑色，防止被 Bloom 等扩散。
Shader "Hidden/Universal Render Pipeline/Stop NaN"
{
    SubShader
    {
        ZTest Always ZWrite Off Cull Off
        Pass
        {
            Name "Stop NaN"
            GLSLPROGRAM
            VARYING vec2 uv;
            #ifdef VERTEX
            void main()
            {
                vec2 p = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);
                uv = p * _BlitScaleBias.xy + _BlitScaleBias.zw;
                gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
            }
            #endif
            #ifdef FRAGMENT
            void main()
            {
                vec3 color = texelFetch(_BlitTexture, ivec2(uv * _BlitTexture_TexelSize.zw), 0).rgb;
                if (any(isnan(color)) || any(isinf(color))) color = vec3(0.0);
                fragColor = vec4(color, 1.0);
            }
            #endif
            ENDGLSL
        }
    }
}
