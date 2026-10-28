// 盒体投影演示：房间的墙和天花板（无光照，颜色来自 RoomPattern）。（GLSL 版，对应 Ch08/RoomWall.shader）
Shader "Cookbook/Ch08/RoomWall"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }
        GLSLINCLUDE
        uniform float _Brightness;
        ENDGLSL

        Pass
        {
            Name "Unlit"
            Tags { "LightMode"="UniversalForwardOnly" }
            GLSLPROGRAM
            #include "Ch08/RoomPattern.glsl"
            VARYING vec3 positionWS;
            VARYING vec3 normalWS;
            #ifdef VERTEX
            void main()
            {
                positionWS = TransformObjectToWorld(positionOS.xyz);
                gl_Position = TransformWorldToHClip(positionWS);
                normalWS = TransformObjectToWorldNormal(normalOS);
            }
            #endif
            #ifdef FRAGMENT
            void main()
            {
                fragColor = vec4(RoomPattern(positionWS, RoomFaceFromNormal(normalWS)) * _Brightness, 1.0);
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
