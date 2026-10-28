// 深度/剔除状态实验台：ZTest、ZWrite、Cull 都是材质属性，可在 Inspector 里直接切换。（GLSL 版）
// 渲染状态写成 [属性名] 的形式，Unity 会在提交绘制时读取材质上的值。
Shader "Cookbook/Ch16/RenderStates"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        #include "Ch16/Ch16Common.glsl"
        uniform vec4 _BaseColor, _BackColor;
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            //#region state
            ZTest [_ZTest]
            ZWrite [_ZWrite]
            Cull [_Cull]
            //#endregion
            GLSLPROGRAM
            #ifdef VERTEX
            void main() { Ch16Vert(); }
            #endif
            #ifdef FRAGMENT
            void main()
            {
                bool front = gl_FrontFacing;
                vec3 N = normalize(normalWS) * (front ? 1.0 : -1.0);
                vec3 albedo = front ? _BaseColor.rgb : _BackColor.rgb;
                fragColor = vec4(SimpleLighting(albedo, N, positionWS, 0.4), 1.0);
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
    }
}
