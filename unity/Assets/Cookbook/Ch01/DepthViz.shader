// 第 1 章 案例 1.3：原始深度 vs 线性深度
// 一个直接在裁剪空间里“摆”出来的全屏四边形：顶点着色器不乘任何矩阵，
// 而是把 Quad 的 [-0.5, 0.5] 顶点直接放到裁剪空间 [-1, 1]，盖满整个屏幕，
// 然后在片元里读取相机深度纹理 _CameraDepthTexture，按 _Mode 显示：
//   0 原始深度（设备深度，Reversed-Z 平台近处为 1）
//   1 Linear01Depth（0 在相机位置，1 在远裁剪面）
//   2 LinearEyeDepth（单位：米），每 _BandWidth 米一条色带
Shader "Cookbook/Ch01/DepthViz"
{
    Properties
    {
        [Enum(Raw,0,Linear01,1,EyeBands,2)] _Mode ("显示", Float) = 0
        _BandWidth ("色带宽度（米）", Float) = 1
        _EyeMax ("眼睛深度着色上限（米）", Float) = 20
    }
    SubShader
    {
        // 透明队列：保证在不透明物体之后画，此时深度纹理已经可用（需要 Depth Texture Mode = After Opaques）
        Tags { "RenderType"="Transparent" "RenderPipeline"="UniversalPipeline" "Queue"="Transparent+100" }

        Pass
        {
            Name "DepthViz"
            Tags { "LightMode"="UniversalForward" }
            ZTest Always
            ZWrite Off
            Cull Off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"   // SRGBToLinear

            CBUFFER_START(UnityPerMaterial)
                float _Mode;
                float _BandWidth;
                float _EyeMax;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
            };

            //#region vert
            Varyings vert(Attributes input)
            {
                Varyings output;
                // 直接给出裁剪空间坐标：w = 1，所以透视除法后 NDC = (x, y)。
                // z 放在近裁剪面 UNITY_NEAR_CLIP_VALUE（D3D/Metal/Vulkan 是 1，OpenGL 是 -1），保证不被裁掉
                output.positionCS = float4(input.positionOS.xy * 2.0, UNITY_NEAR_CLIP_VALUE, 1.0);
                // 渲染到中间 RT 时，Unity 的投影矩阵会上下翻转（_ProjectionParams.x = -1）。
                // 我们绕过了投影矩阵，就要手动跟它保持一致，否则画面会倒过来
                output.positionCS.y *= _ProjectionParams.x;
                return output;
            }
            //#endregion

            //#region frag
            half4 frag(Varyings input) : SV_Target
            {
                // 片元里的 SV_POSITION.xy 是像素坐标，除以屏幕尺寸得到 [0,1] 的屏幕 UV（内部处理了平台翻转）
                float2 uv = GetNormalizedScreenSpaceUV(input.positionCS);
                float raw = SampleSceneDepth(uv);

                int mode = (int)_Mode;
                // 线性色彩空间的工程里，颜色写进 sRGB 目标时会被“提亮”（0.07 显示成约 0.3）。
                // 调试数值时先做一次 SRGBToLinear 抵消它，屏幕上的灰度才等于数值本身。
                if (mode == 0)
                    return half4(SRGBToLinear(raw.xxx), 1);         // 原样输出，不做任何“美化”

                if (mode == 1)
                {
                    float d01 = Linear01Depth(raw, _ZBufferParams);  // 相机处 0（实际从 near/far 开始），远裁剪面处 1
                    return half4(SRGBToLinear(d01.xxx), 1);
                }

                float eye = LinearEyeDepth(raw, _ZBufferParams);    // 单位：米，沿相机前方的距离
                float band = frac(eye / _BandWidth);
                float3 col = lerp(float3(0.10, 0.35, 0.55), float3(0.95, 0.55, 0.25), saturate(eye / _EyeMax));
                col *= 0.55 + 0.45 * step(0.5, band);              // 交替明暗：每条色带一样宽 → 说明 eye 是线性的
                return half4(col, 1);
            }
            //#endregion
            ENDHLSL
        }
    }
}
