// 调试用：把 _CameraDepthTexture 以线性深度灰度图显示出来（贴在相机前的一张面片上）。
// 越近越白，越远越黑；没有出现在深度图里的物体会“消失”。
Shader "Cookbook/Ch03/Debug/DepthView"
{
    Properties
    {
        _Range ("Visible Range (m)", Float) = 12
    }

    SubShader
    {
        // 透明队列：此时深度图已经生成（深度预渲染或 CopyDepth 都在不透明物体之后可用）
        Tags { "RenderType"="Transparent" "RenderPipeline"="UniversalPipeline" "Queue"="Transparent+100" }

        Pass
        {
            Name "DepthView"
            Tags { "LightMode"="UniversalForward" }
            ZWrite Off
            ZTest Always
            Cull Off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float _Range;
            CBUFFER_END

            struct Attributes { float4 positionOS : POSITION; };
            struct Varyings   { float4 positionCS : SV_POSITION; };

            Varyings vert (Attributes input)
            {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                return output;
            }

            half4 frag (Varyings input) : SV_Target
            {
                float2 screenUV = GetNormalizedScreenSpaceUV(input.positionCS);
                float rawDepth = SampleSceneDepth(screenUV);
                float eyeDepth = LinearEyeDepth(rawDepth, _ZBufferParams);   // 单位：米
                half v = saturate(1 - eyeDepth / _Range);
                return half4(v.xxx * v, 1);
            }
            ENDHLSL
        }
    }
}
