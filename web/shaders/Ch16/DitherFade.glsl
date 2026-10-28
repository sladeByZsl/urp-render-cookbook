// 抖动透明（Dither / Screen-door Transparency）：不混合，而是按屏幕位置的阈值图案丢弃一部分像素。（GLSL 版）
// 物体仍然是不透明队列、写深度、不需要排序；代价是近看能看到网点。阴影 Pass 用同样的抖动。
Shader "Cookbook/Ch16/DitherFade"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="AlphaTest" }

        GLSLINCLUDE
        #include "Ch16/Ch16Common.glsl"
        uniform vec4 _BaseColor;
        uniform float _Fade;
        uniform float _DitherShadow;

        //#region bayer
        // 4×4 Bayer 矩阵：16 个阈值均匀分布在 0..1，且相邻像素的阈值尽量“错开”
        float Bayer4x4(uvec2 p)
        {
            const float m[16] = float[16](
                 0.0,  8.0,  2.0, 10.0,
                12.0,  4.0, 14.0,  6.0,
                 3.0, 11.0,  1.0,  9.0,
                15.0,  7.0, 13.0,  5.0);
            p %= 4u;
            return (m[p.y * 4u + p.x] + 0.5) / 16.0;
        }

        #ifdef FRAGMENT
        // opacity 为 0.5 时，正好有一半像素的阈值低于它而被保留
        void DitherClip(vec2 pixelPos, float opacity)
        {
            if (opacity - Bayer4x4(uvec2(pixelPos)) < 0.0) discard;
        }
        #endif
        //#endregion
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            GLSLPROGRAM
            #ifdef VERTEX
            void main() { Ch16Vert(); }
            #endif
            #ifdef FRAGMENT
            void main()
            {
                DitherClip(gl_FragCoord.xy, _Fade);     // gl_FragCoord.xy 在片元里就是像素坐标（对应 HLSL 的 SV_POSITION.xy）
                fragColor = vec4(SimpleLighting(_BaseColor.rgb, normalize(normalWS), positionWS, 0.5), 1.0);
            }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0
            GLSLPROGRAM
            #ifdef VERTEX
            void main() { gl_Position = Ch16ShadowPositionCS(positionOS.xyz, normalOS); }
            #endif
            #ifdef FRAGMENT
            void main()
            {
                // 阴影贴图里的“像素”是阴影贴图的纹素，抖动后经过 PCF 软阴影过滤，会得到浅一些的阴影
                if (_DitherShadow > 0.5) DitherClip(gl_FragCoord.xy, _Fade);
                fragColor = vec4(0.0);
            }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            GLSLPROGRAM
            #ifdef VERTEX
            void main() { gl_Position = TransformObjectToHClip(positionOS.xyz); }
            #endif
            #ifdef FRAGMENT
            void main() { DitherClip(gl_FragCoord.xy, _Fade); fragColor = vec4(gl_FragCoord.z); }
            #endif
            ENDGLSL
        }
    }
}
