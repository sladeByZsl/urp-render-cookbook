// 案例 25.1：最小的全屏效果——反色 / 去色 / 染色。
// 顶点着色器直接用 core 包 Blit.hlsl 里的 Vert（全屏三角形），输入纹理名固定为 _BlitTexture。
Shader "Cookbook/Ch25/Tint"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        // 全屏 Pass 的标配：不测深度、不写深度、不剔除
        ZTest Always ZWrite Off Cull Off

        Pass
        {
            Name "Tint"

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag

            //#region include
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            // Blit.hlsl 提供：_BlitTexture、_BlitScaleBias、Attributes/Varyings、Vert()、sampler_LinearClamp 等
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            //#endregion

            // 这些参数由 C# 每帧写入材质，不放 Properties 块
            float4 _TintColor;    // 乘色
            float  _Invert;       // 0..1 反色程度
            float  _Desaturate;   // 0..1 去色程度

            //#region frag
            half4 Frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                float2 uv = input.texcoord;
                half4 color = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv);

                // 1) 去色：用 Rec.709 亮度权重（相机颜色缓冲是线性空间）
                half luma = dot(color.rgb, half3(0.2126, 0.7152, 0.0722));
                color.rgb = lerp(color.rgb, luma.xxx, _Desaturate);

                // 2) 反色：在 sRGB（感知）空间里做 1-x 才像“底片”，在线性空间直接反会整体发白
                half3 srgb = LinearToSRGB(saturate(color.rgb));
                half3 inverted = SRGBToLinear(1.0 - srgb);
                color.rgb = lerp(color.rgb, inverted, _Invert);

                // 3) 染色
                color.rgb *= _TintColor.rgb;
                return color;
            }
            //#endregion
            ENDHLSL
        }
    }
}
