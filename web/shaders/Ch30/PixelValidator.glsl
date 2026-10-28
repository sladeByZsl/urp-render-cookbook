// 30.7 节：像素校验全屏 Pass——把 NaN / Inf / 负数 / 超范围的像素涂成醒目的颜色。（GLSL 版，对应 Ch30/PixelValidator.shader）
// 与 Rendering Debugger 里的 “Highlight NaN, Inf and Negative Values” 思路相同，但可以放进任何管线阶段。
Shader "Cookbook/Ch30/PixelValidator"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        ZWrite Off ZTest Always Cull Off Blend Off
        Pass
        {
            Name "Validate"
            GLSLPROGRAM
            uniform float _MaxValue;

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
            // core 包 Common.hlsl 的 AnyIsNaN / AnyIsInf：GLSL 有内置的 isnan / isinf
            bool AnyIsNaN(vec4 v) { return any(isnan(v)); }
            bool AnyIsInf(vec4 v) { return any(isinf(v)); }

            //#region validate
            void main()
            {
                vec4 c = texelFetch(_BlitTexture, ivec2(texcoord * _BlitTexture_TexelSize.zw), 0);
                // 背景压暗、去色，让标记更显眼
                vec3 bg = vec3(Luminance(saturate(c.rgb)) * 0.35);
                if (AnyIsNaN(c))                                   { fragColor = vec4(1, 0, 1, 1); return; }   // 品红：NaN
                if (AnyIsInf(c))                                   { fragColor = vec4(0, 1, 1, 1); return; }   // 青：Inf
                if (any(lessThan(c.rgb, vec3(0.0))))               { fragColor = vec4(1, 1, 0, 1); return; }   // 黄：负数
                if (any(greaterThan(c.rgb, vec3(_MaxValue))))      { fragColor = vec4(1, 0.3, 0, 1); return; } // 橙：异常大的 HDR 值
                fragColor = vec4(bg, 1.0);
            }
            //#endregion
            #endif
            ENDGLSL
        }
    }
}
