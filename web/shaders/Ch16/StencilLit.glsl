// 带模板测试参数的简单受光 Shader：Ref/Comp/Pass 全部做成材质属性。（GLSL 版）
// 用它可以搭出“只在模板值等于 1 的地方可见”的物体（传送门里的世界），或者“画的时候顺便写模板”的物体（X 光的角色）。
Shader "Cookbook/Ch16/StencilLit"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        #include "Ch16/Ch16Common.glsl"
        uniform vec4 _BaseMap_ST;
        uniform vec4 _BaseColor;
        uniform float _Unlit;
        uniform sampler2D _BaseMap;
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            Cull [_Cull]
            //#region stencil
            Stencil
            {
                Ref  [_StencilRef]
                Comp [_StencilComp]
                Pass [_StencilPass]
            }
            //#endregion
            GLSLPROGRAM
            #ifdef VERTEX
            void main() { Ch16Vert(); }
            #endif
            #ifdef FRAGMENT
            void main()
            {
                vec3 albedo = texture(_BaseMap, TransformTex(uv, _BaseMap_ST)).rgb * _BaseColor.rgb;
                if (_Unlit > 0.5) { fragColor = vec4(albedo, 1.0); return; }
                fragColor = vec4(SimpleLighting(albedo, normalize(normalWS), positionWS, 0.3), 1.0);
            }
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
