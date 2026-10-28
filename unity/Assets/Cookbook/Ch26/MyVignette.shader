// 案例 26.6：暗角。以 center 为圆心，半径越大越接近 _VignetteColor。
Shader "Cookbook/Ch26/MyVignette"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        ZTest Always ZWrite Off Cull Off
        Pass
        {
            Name "Vignette"
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float4 _VignetteColor;
            float4 _VignetteParams;   // xy 中心, z 强度, w 柔和度
            float  _VignetteRounded;

            //#region frag
            half4 Frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                float2 uv = input.texcoord;
                half4 color = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv);

                float2 d = (uv - _VignetteParams.xy) * 2.0;                 // 屏幕边缘中点处 |d| = 1
                d.x *= lerp(1.0, _ScreenParams.x / _ScreenParams.y, _VignetteRounded);
                float r = length(d);

                // 强度决定暗角从哪里开始，柔和度决定过渡带宽度
                float inner = 1.3 - _VignetteParams.z;
                half mask = smoothstep(inner, inner + _VignetteParams.w, r);
                color.rgb = lerp(color.rgb, _VignetteColor.rgb, mask);
                return color;
            }
            //#endregion
            ENDHLSL
        }
    }
}
