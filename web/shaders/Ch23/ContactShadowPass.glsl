// 案例 23.9：接触阴影的全屏步进 Pass（由 ContactShadowFeature 调用）（GLSL 版）。
Shader "Cookbook/Ch23/ContactShadowPass"
{
    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" }
        Pass
        {
            Name "ContactShadows"
            ZTest Always ZWrite Off Cull Off

            GLSLPROGRAM
            uniform vec4 _ContactParams;    // x: 追踪长度  y: 步数  z: 厚度  w: 起点偏移
            uniform vec4 _ContactLightDir;  // xyz: 指向光源的方向 L   w: 强度

            VARYING vec2 texcoord;

            #ifdef VERTEX
            // 全屏三角形（Blit.hlsl 的 Vert）
            void main()
            {
                vec2 p = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);
                texcoord = p;
                gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
            }
            #endif

            #ifdef FRAGMENT
            // core 库 Random.hlsl 里的交错梯度噪声
            float InterleavedGradientNoise(vec2 pixCoord, int frameCount)
            {
                const vec3 magic = vec3(0.06711056, 0.00583715, 52.9829189);
                vec2 frameMagicScale = vec2(2.083, 4.867);
                pixCoord += float(frameCount) * frameMagicScale;
                return fract(magic.z * fract(dot(pixCoord, magic.xy)));
            }
            // 世界坐标 → 0~1 屏幕 UV（WebGL 不翻转 y）
            vec2 ComputeNormalizedDeviceCoordinates(vec3 position, mat4 clipSpaceTransform)
            {
                vec4 positionCS = clipSpaceTransform * vec4(position, 1.0);
                return positionCS.xy / positionCS.w * 0.5 + 0.5;
            }

            //#region march
            float Frag()
            {
                vec2 uv = texcoord;
                float deviceDepth = SampleSceneDepth(uv);
                // WebGL 深度不反转：远平面是 1
                if (deviceDepth >= 1.0) return 1.0;            // 天空：不处理
                // 1) 由深度重建这个像素的世界坐标（GLSL 版 ComputeWorldSpacePosition 内部已把 0~1 深度换成 -1~1）
                vec3 positionWS = ComputeWorldSpacePosition(uv, deviceDepth, UNITY_MATRIX_I_VP);

                int   steps     = int(_ContactParams.y);
                float stepLen   = _ContactParams.x / _ContactParams.y;
                float thickness = _ContactParams.z;
                vec3 L = _ContactLightDir.xyz;

                // 2) 用交错梯度噪声抖动起点，把条带状走样变成细噪点（软阴影 / TAA 会再把它抹平）
                float jitter = InterleavedGradientNoise(uv * _ScreenParams.xy, 0);
                vec3 p = positionWS + L * (_ContactParams.w + stepLen * jitter);

                float occlusion = 0.0;
                for (int i = 0; i < steps; i++)
                {
                    p += L * stepLen;
                    // 3) 把采样点投回屏幕，读那里的场景深度
                    vec4 positionCS = TransformWorldToHClip(p);
                    vec2 sampleUV = ComputeNormalizedDeviceCoordinates(p, UNITY_MATRIX_VP);
                    if (any(lessThan(sampleUV, vec2(0.0))) || any(greaterThan(sampleUV, vec2(1.0)))) break;

                    float sceneEyeDepth  = LinearEyeDepth(SampleSceneDepth(sampleUV), _ZBufferParams);
                    float sampleEyeDepth = positionCS.w;           // 透视投影下 w 就是观察空间深度
                    float delta = sampleEyeDepth - sceneEyeDepth;  // > 0：采样点在可见表面之后

                    // 4) 在表面之后、但又没“穿透”太深 → 光线被这块表面挡住了
                    if (delta > 0.002 && delta < thickness)
                    {
                        // 离起点越远的遮挡越弱，避免接触阴影末端出现硬边
                        occlusion = 1.0 - float(i) / float(steps);
                        break;
                    }
                }
                return 1.0 - occlusion * _ContactLightDir.w;
            }
            //#endregion
            void main() { fragColor = vec4(Frag()); }
            #endif
            ENDGLSL
        }
    }
}
