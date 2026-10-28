// 案例 29.1 的反例：能编译、能显示，但 SRP Batcher 不兼容。（GLSL 版，对应 Ch29/BatcherBreaker.shader）
// 原因：_BaseColor 声明在 CBUFFER 之外，变成了“全局 uniform”，每个材质都要单独 SetPass 上传。
// （WebGL 没有 SRP Batcher 和 CBUFFER，GLSL 版里两种写法没有区别，只为和 HLSL 对照）
Shader "Cookbook/Ch29/BatcherBreaker"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }
        Pass
        {
            Tags { "LightMode"="UniversalForward" }
            GLSLPROGRAM
            //#region bad
            uniform vec4 _BaseColor;     // ✗ 不在 UnityPerMaterial 里
            //#endregion

            #ifdef VERTEX
            void main() { gl_Position = TransformObjectToHClip(positionOS.xyz); }
            #endif
            #ifdef FRAGMENT
            void main() { fragColor = _BaseColor; }
            #endif
            ENDGLSL
        }
    }
}
