// 第 29 章配图用的简单透明面片（烟雾一类的粒子替身）：Alpha 混合、不写深度。（GLSL 版，对应 Ch29/SoftQuad.shader）
Shader "Cookbook/Ch29/SoftQuad"
{
    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent" "RenderPipeline"="UniversalPipeline" "IgnoreProjector"="True" }
        Pass
        {
            Name "Unlit"
            Tags { "LightMode"="UniversalForward" }
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            Cull Off
            GLSLPROGRAM
            uniform sampler2D _BaseMap;
            uniform vec4 _BaseMap_ST;
            uniform vec4 _BaseColor;

            VARYING vec2 uv;
            #ifdef VERTEX
            void main()
            {
                gl_Position = TransformObjectToHClip(positionOS.xyz);
                uv = TransformTex(texcoord0.xy, _BaseMap_ST);
            }
            #endif
            #ifdef FRAGMENT
            void main() { fragColor = texture(_BaseMap, uv) * _BaseColor; }
            #endif
            ENDGLSL
        }
    }
}
