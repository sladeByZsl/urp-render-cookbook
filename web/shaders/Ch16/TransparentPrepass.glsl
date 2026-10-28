// 双 Pass 半透明：第一个 Pass 只写深度（不写颜色），第二个 Pass 用 LEqual 正常混合。（GLSL 版）
// 结果是每个像素只留下“离相机最近的那层表面”，自身前后层次不再错乱。
// URP 的 DrawObjectsPass 按 SRPDefaultUnlit → UniversalForward 的顺序绘制同一物体的多个 Pass，
// 所以把预深度放在 SRPDefaultUnlit 里，就能保证它先于颜色 Pass 执行。
Shader "Cookbook/Ch16/TransparentPrepass"
{
    SubShader
    {
        Tags { "RenderType"="Transparent" "RenderPipeline"="UniversalPipeline" "Queue"="Transparent" }

        GLSLINCLUDE
        #include "Ch16/Ch16Common.glsl"
        uniform vec4 _BaseColor;
        ENDGLSL

        //#region prepass
        Pass
        {
            Name "DepthPrepass"
            Tags { "LightMode"="SRPDefaultUnlit" }
            ZWrite On
            ColorMask 0          // 只写深度，不动颜色
            GLSLPROGRAM
            #ifdef VERTEX
            void main() { gl_Position = TransformObjectToHClip(positionOS.xyz); }
            #endif
            #ifdef FRAGMENT
            void main() { fragColor = vec4(0.0); }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            ZTest LEqual         // 深度相等的那层（最前面的表面）才能通过
            GLSLPROGRAM
            #ifdef VERTEX
            void main() { Ch16Vert(); }
            #endif
            #ifdef FRAGMENT
            void main()
            {
                fragColor = vec4(SimpleLighting(_BaseColor.rgb, normalize(normalWS), positionWS, 0.8), _BaseColor.a);
            }
            #endif
            ENDGLSL
        }
        //#endregion
    }
}
