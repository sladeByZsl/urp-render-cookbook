// 调试用：按法线方向采样一张 cubemap 并原样显示（看环境本身，或看预先积分好的辐照度图）。（GLSL 版，对应 Ch08/CubeDisplay.shader）
Shader "Cookbook/Ch08/CubeDisplay"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }
        GLSLINCLUDE
        uniform vec4  _Albedo;
        uniform float _Exposure;
        ENDGLSL
        Pass
        {
            Name "Unlit"
            Tags { "LightMode"="UniversalForwardOnly" }
            GLSLPROGRAM
            uniform samplerCube _Cube;
            VARYING vec3 normalWS;
            #ifdef VERTEX
            void main()
            {
                gl_Position = TransformObjectToHClip(positionOS.xyz);
                normalWS = TransformObjectToWorldNormal(normalOS);
            }
            #endif
            #ifdef FRAGMENT
            void main()
            {
                vec3 c = textureLod(_Cube, normalize(normalWS), 0.0).rgb;
                fragColor = vec4(c * _Albedo.rgb * _Exposure, 1.0);
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
            #include "Ch08/Ch08Passes.glsl"
            #ifdef VERTEX
            void main() { gl_Position = Ch08DepthVert(); }
            #endif
            #ifdef FRAGMENT
            void main() { fragColor = Ch08NullFrag(); }
            #endif
            ENDGLSL
        }
    }
}
