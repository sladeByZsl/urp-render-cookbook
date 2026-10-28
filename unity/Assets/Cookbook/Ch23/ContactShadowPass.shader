// 案例 23.9：接触阴影的全屏步进 Pass（由 ContactShadowFeature 调用）。
Shader "Cookbook/Ch23/ContactShadowPass"
{
    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" }
        Pass
        {
            Name "ContactShadows"
            ZTest Always ZWrite Off Cull Off

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Random.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            float4 _ContactParams;    // x: 追踪长度  y: 步数  z: 厚度  w: 起点偏移
            float4 _ContactLightDir;  // xyz: 指向光源的方向 L   w: 强度

            //#region march
            half Frag(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;
                float deviceDepth = SampleSceneDepth(uv);
            #if UNITY_REVERSED_Z
                if (deviceDepth <= 0.0) return 1;              // 天空：不处理
            #else
                if (deviceDepth >= 1.0) return 1;
                deviceDepth = deviceDepth * 2.0 - 1.0;
            #endif
                // 1) 由深度重建这个像素的世界坐标
                float3 positionWS = ComputeWorldSpacePosition(uv, deviceDepth, UNITY_MATRIX_I_VP);

                int   steps     = (int)_ContactParams.y;
                float stepLen   = _ContactParams.x / _ContactParams.y;
                float thickness = _ContactParams.z;
                float3 L = _ContactLightDir.xyz;

                // 2) 用交错梯度噪声抖动起点，把条带状走样变成细噪点（软阴影 / TAA 会再把它抹平）
                float jitter = InterleavedGradientNoise(uv * _ScreenSize.xy, 0);
                float3 p = positionWS + L * (_ContactParams.w + stepLen * jitter);

                half occlusion = 0;
                [loop] for (int i = 0; i < steps; i++)
                {
                    p += L * stepLen;
                    // 3) 把采样点投回屏幕，读那里的场景深度
                    float4 positionCS = TransformWorldToHClip(p);
                    float2 sampleUV = ComputeNormalizedDeviceCoordinates(p, UNITY_MATRIX_VP);
                    if (any(sampleUV < 0) || any(sampleUV > 1)) break;

                    float sceneEyeDepth  = LinearEyeDepth(SampleSceneDepth(sampleUV), _ZBufferParams);
                    float sampleEyeDepth = positionCS.w;           // 透视投影下 w 就是观察空间深度
                    float delta = sampleEyeDepth - sceneEyeDepth;  // > 0：采样点在可见表面之后

                    // 4) 在表面之后、但又没“穿透”太深 → 光线被这块表面挡住了
                    if (delta > 0.002 && delta < thickness)
                    {
                        // 离起点越远的遮挡越弱，避免接触阴影末端出现硬边
                        occlusion = 1.0 - (float)i / steps;
                        break;
                    }
                }
                return 1.0 - occlusion * _ContactLightDir.w;
            }
            //#endregion
            ENDHLSL
        }
    }
}
