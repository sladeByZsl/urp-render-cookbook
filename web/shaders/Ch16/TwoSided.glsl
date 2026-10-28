// 双面材质：Cull Off 让背面也画出来；但背面的插值法线仍朝“外”，必须按 gl_FrontFacing（HLSL 的 SV_IsFrontFace）翻转，
// 否则背面的光照是反的。背面还可以用另一种颜色（例如纸张、叶片的背面更浅）。（GLSL 版）
Shader "Cookbook/Ch16/TwoSided"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        #include "Ch16/Ch16Common.glsl"
        uniform vec4 _BaseColor, _BackColor;
        uniform float _FlipBackNormal;
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            Cull [_Cull]
            GLSLPROGRAM
            #ifdef VERTEX
            void main() { Ch16Vert(); }
            #endif
            #ifdef FRAGMENT
            //#region frag
            void main()
            {
                // GLSL 直接用内置的 gl_FrontFacing（bool）
                bool isFront = gl_FrontFacing;
                vec3 N = normalize(normalWS);
                if (!isFront && _FlipBackNormal > 0.5) N = -N;
                vec3 albedo = isFront ? _BaseColor.rgb : _BackColor.rgb;
                fragColor = vec4(SimpleLighting(albedo, N, positionWS, 0.3), 1.0);
            }
            //#endregion
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0 Cull [_Cull]
            GLSLPROGRAM
            #ifdef VERTEX
            void main() { gl_Position = Ch16ShadowPositionCS(positionOS.xyz, normalOS); }
            #endif
            #ifdef FRAGMENT
            void main() { fragColor = vec4(0.0); }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R Cull [_Cull]
            GLSLPROGRAM
            #ifdef VERTEX
            void main() { gl_Position = TransformObjectToHClip(positionOS.xyz); }
            #endif
            #ifdef FRAGMENT
            void main() { fragColor = vec4(gl_FragCoord.z); }
            #endif
            ENDGLSL
        }
    }
}
