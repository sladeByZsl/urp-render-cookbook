// 传送门遮罩：不写颜色、不写深度，只把模板缓冲里自己覆盖的像素改成 Ref。（GLSL 版）
// 队列比普通不透明物体早（Geometry-10），保证“门里的世界”绘制时模板已经写好。
Shader "Cookbook/Ch16/StencilMask"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry-10" }

        Pass
        {
            Name "Mask"
            Tags { "LightMode"="UniversalForwardOnly" }
            //#region state
            ColorMask 0
            ZWrite Off
            Cull Off
            Stencil
            {
                Ref [_StencilRef]
                Comp Always
                Pass Replace      // 通过（含深度测试）就把模板值替换为 Ref
            }
            //#endregion
            GLSLPROGRAM
            #ifdef VERTEX
            void main() { gl_Position = TransformObjectToHClip(positionOS.xyz); }
            #endif
            #ifdef FRAGMENT
            void main() { fragColor = vec4(0.0); }
            #endif
            ENDGLSL
        }
    }
}
