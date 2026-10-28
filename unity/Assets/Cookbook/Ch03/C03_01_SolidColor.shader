// 第 1 步：最小可运行的 URP Shader —— 把物体涂成一个纯色。
// 故意保持最少的代码：一个 Pass、一个颜色属性、顶点变换 + 输出颜色。
Shader "Cookbook/Ch03/SolidColor"
{
    Properties
    {
        // 名字 ("Inspector 显示名", 类型) = 默认值
        _BaseColor ("Base Color", Color) = (1, 0.5, 0.2, 1)
    }

    SubShader
    {
        // RenderPipeline 标签：只有 URP 激活时才使用这个 SubShader
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        Pass
        {
            Name "Unlit"
            // UniversalForward：URP 前向渲染的主 Pass（不写 LightMode 时按 SRPDefaultUnlit 处理）
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            // URP 的“地基”：矩阵、坐标变换函数、平台宏都在这里
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            //#region io
            // 顶点着色器的输入：由网格提供，语义 POSITION 告诉 GPU 取哪一路顶点数据
            struct Attributes
            {
                float4 positionOS : POSITION;   // OS = Object Space，模型空间
            };

            // 顶点 → 片元的数据：SV_POSITION 是光栅化必须的齐次裁剪空间坐标
            struct Varyings
            {
                float4 positionCS : SV_POSITION; // CS = Clip Space，裁剪空间
            };
            //#endregion

            // 第 1 步先不放 CBUFFER，第 6 步再讲为什么必须放进去
            half4 _BaseColor;

            //#region vertfrag
            Varyings vert (Attributes input)
            {
                Varyings output;
                // 模型空间 → 世界空间 → 观察空间 → 裁剪空间，一次做完
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                return output;
            }

            half4 frag (Varyings input) : SV_Target
            {
                return _BaseColor;
            }
            //#endregion
            ENDHLSL
        }
    }
}
