// 第 1 章 案例 1.4：透视校正插值 vs 仿射插值
// 同一份 UV，一份用默认插值（透视校正），一份加 noperspective 修饰（屏幕空间线性插值），
// 用 _Affine 选择用哪一份去采样棋盘格。
// （GLSL 版）WebGL2 的 GLSL ES 3.00 没有 noperspective 修饰符，这里用等价的写法模拟：
// 顶点里输出 uv·w 和 w 两个（默认透视校正插值的）变量，片元里相除，结果正好是屏幕空间线性插值。
Shader "Cookbook/Ch01/PerspectiveInterp"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        Pass
        {
            Name "Interp"
            Tags { "LightMode"="UniversalForward" }
            Cull Off

            GLSLPROGRAM
            uniform sampler2D _MainTex;
            uniform float _Tiling;
            uniform float _Affine;

            //#region varyings
            VARYING vec2 uv;            // 默认：透视校正插值
            VARYING vec2 uvAffineW;     // noperspective 的模拟：uv × w
            VARYING float clipW;        //                      w
            //#endregion

            #ifdef VERTEX
            void main()
            {
                gl_Position = TransformObjectToHClip(positionOS.xyz);
                uv = texcoord0.xy * _Tiling;
                uvAffineW = texcoord0.xy * _Tiling * gl_Position.w;
                clipW = gl_Position.w;
            }
            #endif

            #ifdef FRAGMENT
            void main()
            {
                // 透视校正插值后 (uv·w) / w 的结果 = uv 在屏幕空间里线性插值（PS1 时代的效果）
                vec2 uvAffine = uvAffineW / clipW;
                vec2 st = _Affine > 0.5 ? uvAffine : uv;
                fragColor = texture(_MainTex, st);
            }
            #endif
            ENDGLSL
        }
    }
}
