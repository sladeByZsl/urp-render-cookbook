// 第 1 步：最小可运行的 URP Shader —— 把物体涂成一个纯色。
// 故意保持最少的代码：一个 Pass、一个颜色属性、顶点变换 + 输出颜色。
Shader "Cookbook/Ch03/SolidColor"
{
    SubShader
    {
        // RenderPipeline 标签：只有 URP 激活时才使用这个 SubShader
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        Pass
        {
            Name "Unlit"
            // UniversalForward：URP 前向渲染的主 Pass（不写 LightMode 时按 SRPDefaultUnlit 处理）
            Tags { "LightMode"="UniversalForward" }

            GLSLPROGRAM
            // Core.glsl（URP 的“地基”：矩阵、坐标变换函数）网页引擎会自动包含

            //#region io
            // 顶点着色器的输入：由网格提供，GLSL 里是固定名字的 in 变量 positionOS（OS = Object Space，模型空间）
            // 顶点 → 片元的数据：光栅化必须的齐次裁剪空间坐标写进内置变量 gl_Position（CS = Clip Space，裁剪空间）
            //#endregion

            // 第 1 步先不放 CBUFFER，第 6 步再讲为什么必须放进去
            uniform vec4 _BaseColor;

            //#region vertfrag
            #ifdef VERTEX
            void main()
            {
                // 模型空间 → 世界空间 → 观察空间 → 裁剪空间，一次做完
                gl_Position = TransformObjectToHClip(positionOS.xyz);
            }
            #endif

            #ifdef FRAGMENT
            void main()
            {
                fragColor = _BaseColor;
            }
            #endif
            //#endregion
            ENDGLSL
        }
    }
}
