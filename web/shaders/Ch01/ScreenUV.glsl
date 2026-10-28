// 第 1 章 案例 1.5：屏幕 UV 应该在哪里做除法
// 用屏幕 UV 采样一个程序化棋盘格。三种写法：
//   0 正确：顶点里输出未除 w 的 positionNDC，片元里再除（URP 的 positionNDC / 旧的 ComputeScreenPos 就是为此设计）
//   1 错误：顶点里先除 w，再交给默认的透视校正插值
//   2 也正确：顶点里先除 w，但用 noperspective 在屏幕空间线性插值
//   3 最省事：片元里直接用 SV_POSITION（gl_FragCoord）算 GetNormalizedScreenSpaceUV
// （GLSL 版）GLSL ES 3.00 没有 noperspective，写法 2 用“uv·w 与 w 分别插值、片元里相除”来模拟，结果相同。
Shader "Cookbook/Ch01/ScreenUV"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        Pass
        {
            Name "ScreenUV"
            Tags { "LightMode"="UniversalForward" }
            Cull Off

            GLSLPROGRAM
            uniform float _Mode;
            uniform float _Cells;

            //#region code
            VARYING vec4 vPositionNDC;     // 齐次屏幕坐标 (x, y, z, w)，xy 在 [0, w]
            VARYING vec2 vUvDivided;       // 顶点里已经除过 w
            VARYING vec2 vUvDividedNPw;    // 同上，但按屏幕空间线性插值（noperspective 的模拟：先乘 w）
            VARYING float vClipW;

            #ifdef VERTEX
            void main()
            {
                VertexPositionInputs pos = GetVertexPositionInputs(positionOS.xyz);
                gl_Position   = pos.positionCS;
                vPositionNDC  = pos.positionNDC;
                vUvDivided    = pos.positionNDC.xy / pos.positionNDC.w;
                vUvDividedNPw = pos.positionNDC.xy / pos.positionNDC.w * pos.positionCS.w;
                vClipW        = pos.positionCS.w;
            }
            #endif

            #ifdef FRAGMENT
            float Checker(vec2 uv)
            {
                float aspect = _ScreenParams.x / _ScreenParams.y;
                vec2 cell = floor(uv * vec2(_Cells * aspect, _Cells));
                float s = abs(cell.x + cell.y);
                return s - 2.0 * trunc(s / 2.0);   // fmod(s, 2)
            }

            void main()
            {
                vec2 uv;
                int mode = int(_Mode);
                if (mode == 0)      uv = vPositionNDC.xy / vPositionNDC.w;   // 插值之后再除
                else if (mode == 1) uv = vUvDivided;
                else if (mode == 2) uv = vUvDividedNPw / vClipW;
                else                uv = GetNormalizedScreenSpaceUV(gl_FragCoord);

                float k = Checker(uv);
                vec3 col = mix(vec3(0.92, 0.92, 0.94), vec3(0.12, 0.42, 0.56), k);
                fragColor = vec4(col, 1);
            }
            #endif
            //#endregion
            ENDGLSL
        }
    }
}
