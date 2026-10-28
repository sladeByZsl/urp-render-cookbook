// 案例 25.6：读取遮罩 RT，膨胀求外轮廓，再用 Alpha 混合叠到相机颜色上。
// Pass 0：描边 + 填充（混合叠加）；Pass 1：调试用，直接把遮罩显示成灰度（不混合）。
Shader "Cookbook/Ch25/LayerOutline"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        ZTest Always ZWrite Off Cull Off

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

        float4 _BlitTexture_TexelSize;   // Unity 绑定纹理时自动填写 (1/w, 1/h, w, h)
        float4 _OutlineColor;
        float4 _FillColor;
        float  _OutlineWidth;            // 像素

        half Mask(float2 uv) { return SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv).r; }
        ENDHLSL

        Pass
        {
            Name "Outline"
            Blend SrcAlpha OneMinusSrcAlpha

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag

            //#region frag
            half4 Frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                float2 uv = input.texcoord;
                half center = Mask(uv);

                // 膨胀（Dilation）：在半径 = 线宽、线宽/2 的两圈圆周上各取 12 个样本，求最大值
                float2 r = _BlitTexture_TexelSize.xy * _OutlineWidth;
                half dilated = center;
                [unroll] for (int k = 0; k < 12; k++)
                {
                    float a = k * (TWO_PI / 12.0);
                    float2 dir = float2(cos(a), sin(a));
                    dilated = max(dilated, Mask(uv + dir * r));
                    dilated = max(dilated, Mask(uv + dir * r * 0.5));
                }

                // 膨胀后的区域减去原区域 = 物体外侧一圈
                half outline = saturate(dilated - center);
                half3 rgb = lerp(_FillColor.rgb, _OutlineColor.rgb, outline);
                half alpha = outline * _OutlineColor.a + center * _FillColor.a;
                return half4(rgb, alpha);
            }
            //#endregion
            ENDHLSL
        }

        Pass
        {
            Name "DebugMask"
            Blend Off
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment FragDebug
            half4 FragDebug(Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                half m = Mask(input.texcoord);
                return half4(lerp(half3(0.03, 0.04, 0.06), half3(1, 1, 1), m), 1);
            }
            ENDHLSL
        }
    }
}
