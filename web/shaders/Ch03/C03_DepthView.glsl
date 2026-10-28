// 调试用：把 _CameraDepthTexture 以线性深度灰度图显示出来（贴在相机前的一张面片上）。
// 越近越白，越远越黑；没有出现在深度图里的物体会“消失”。
Shader "Cookbook/Ch03/Debug/DepthView"
{
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

            GLSLPROGRAM
            // _CameraDepthTexture / SampleSceneDepth 由 Core.glsl 提供（对应 DeclareDepthTexture.hlsl）
            uniform float _Range;

            #ifdef VERTEX
            void main()
            {
                gl_Position = TransformObjectToHClip(positionOS.xyz);
            }
            #endif

            #ifdef FRAGMENT
            void main()
            {
                vec2 screenUV = GetNormalizedScreenSpaceUV(gl_FragCoord);
                float rawDepth = SampleSceneDepth(screenUV);
                float eyeDepth = LinearEyeDepth(rawDepth, _ZBufferParams);   // 单位：米
                float v = saturate(1.0 - eyeDepth / _Range);
                fragColor = vec4(vec3(v) * v, 1);
            }
            #endif
            ENDGLSL
        }
    }
}
