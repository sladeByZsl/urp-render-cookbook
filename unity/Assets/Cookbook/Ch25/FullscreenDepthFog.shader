// 案例 25.3：Full Screen Pass + Requirements=Depth —— 读取 _CameraDepthTexture 做距离雾。
Shader "Cookbook/Ch25/FullscreenDepthFog"
{
    Properties
    {
        _FogColor ("Fog Color", Color) = (0.62, 0.68, 0.76, 1)
        _FogStart ("Fog Start (m)", Float) = 2
        _FogDensity ("Fog Density", Range(0, 1)) = 0.18
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        ZTest Always ZWrite Off Cull Off

        Pass
        {
            Name "DepthFog"
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            // 声明 _CameraDepthTexture 与 SampleSceneDepth()
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _FogColor;
                float  _FogStart;
                float  _FogDensity;
            CBUFFER_END

            //#region frag
            half4 Frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                float2 uv = input.texcoord;
                half4 color = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv);

                // 原始深度 → 观察空间线性深度（米）。Reversed-Z 的差异由 _ZBufferParams 处理
                float rawDepth = SampleSceneDepth(uv);
                float eyeDepth = LinearEyeDepth(rawDepth, _ZBufferParams);

                // 指数雾：f = 1 - e^(-density * 距离)
                float dist = max(eyeDepth - _FogStart, 0.0);
                half fog = 1.0 - exp(-_FogDensity * dist);
                color.rgb = lerp(color.rgb, _FogColor.rgb, fog);
                return color;
            }
            //#endregion
            ENDHLSL
        }
    }
}
