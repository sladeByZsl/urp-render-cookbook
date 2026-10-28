// 案例 29.5：Overdraw 计数。作为 overrideMaterial 替换场景里所有物体的材质，（GLSL 版，对应 Ch29/OverdrawCount.shader）
// 每画一层片元就往 R 通道加 1（加法混合），最后得到“每个像素被着色了几次”。
Shader "Cookbook/Ch29/OverdrawCount"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        Pass
        {
            Name "Count"
            //#region state
            Blend One One          // 累加
            ZWrite Off
            ZTest [_ZTest]
            Cull [_Cull]
            //#endregion
            GLSLPROGRAM
            #ifdef VERTEX
            void main() { gl_Position = TransformObjectToHClip(positionOS.xyz); }
            #endif
            #ifdef FRAGMENT
            void main() { fragColor = vec4(1, 0, 0, 0); }
            #endif
            ENDGLSL
        }
    }
}
