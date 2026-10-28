// 把 DFG 查找表画到面片上：横轴 NoV（0→1），纵轴感知粗糙度（下 0 → 上 1）（GLSL 版，对应 Ch11/DFGLutView.shader）
// R = A（F0 的系数），G = B（F90 的偏置）
Shader "Cookbook/Ch11/DFGLutView"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }
        Pass
        {
            Tags { "LightMode"="UniversalForward" }
            GLSLPROGRAM
            uniform float _Mode;
            uniform sampler2D _DFGLut;
            #include "Ch11/MyPBR_BRDF.glsl"

            VARYING vec2 uv;
            #ifdef VERTEX
            void main() { gl_Position = TransformObjectToHClip(positionOS.xyz); uv = texcoord0.xy; }
            #endif

            #ifdef FRAGMENT
            void main()
            {
                vec2 lut = textureLod(_DFGLut, uv, 0.0).rg;
                vec2 ana = MyEnvDFGApprox(uv.x, uv.y);
                vec2 c = _Mode < 0.5 ? lut : (_Mode < 1.5 ? ana : abs(lut - ana) * 4.0);
                // 目标是 sRGB 的 RT：输出线性值，硬件会做 sRGB 编码，图上看到的是“感知均匀”的亮度
                fragColor = vec4(c, 0.0, 1.0);
            }
            #endif
            ENDGLSL
        }
    }
}
