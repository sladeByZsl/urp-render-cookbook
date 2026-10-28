// 最普通的半透明受光材质：Alpha 混合、默认不写深度。ZWrite 与 Cull 做成属性，用来复现排序问题。（GLSL 版）
Shader "Cookbook/Ch16/TransparentLit"
{
    SubShader
    {
        Tags { "RenderType"="Transparent" "RenderPipeline"="UniversalPipeline" "Queue"="Transparent" }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite [_ZWrite]
            Cull [_Cull]
            GLSLPROGRAM
            #include "Ch16/Ch16Common.glsl"
            uniform vec4 _BaseColor;

            #ifdef VERTEX
            void main() { Ch16Vert(); }
            #endif
            #ifdef FRAGMENT
            void main()
            {
                vec3 N = normalize(normalWS) * (gl_FrontFacing ? 1.0 : -1.0);
                fragColor = vec4(SimpleLighting(_BaseColor.rgb, N, positionWS, 0.8), _BaseColor.a);
            }
            #endif
            ENDGLSL
        }
    }
}
