// 第 2 章 2.10 节 / 案例 2.6：一个“看起来没问题”、却不兼容 SRP Batcher 的 Shader
// 问题：_BaseColor 是材质属性，却声明在 CBUFFER 之外。Inspector 里会显示
// “SRP Batcher: not compatible”，原因是 “Material property is found in another cbuffer than UnityPerMaterial”。
// （GLSL 版）WebGL 没有 SRP Batcher，也没有 CBUFFER 的区别：材质属性都是普通 uniform，画面和兼容版完全一样。
Shader "Cookbook/Ch02/SrpBatcherBroken"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }
        Pass
        {
            Tags { "LightMode"="UniversalForward" }
            GLSLPROGRAM
            //#region broken
            uniform sampler2D _BaseMap;
            uniform vec4 _BaseMap_ST;     // ✗ 不在 UnityPerMaterial 里
            uniform vec4 _BaseColor;      // ✗ 不在 UnityPerMaterial 里
            //#endregion

            VARYING vec2 uv;

            #ifdef VERTEX
            void main()
            {
                gl_Position = TransformObjectToHClip(positionOS.xyz);
                uv = TransformTex(texcoord0.xy, _BaseMap_ST);
            }
            #endif
            #ifdef FRAGMENT
            void main()
            {
                fragColor = texture(_BaseMap, uv) * _BaseColor;
            }
            #endif
            ENDGLSL
        }
    }
}
