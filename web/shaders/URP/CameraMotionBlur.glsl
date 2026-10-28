// URP 14 CameraMotionBlur.shader 的 GLSL 版：只考虑相机运动。
// 用深度重建世界坐标，分别投影到“上一帧”和“这一帧”的裁剪空间，差值就是屏幕速度，沿速度方向前后各采样 N 次。
// 三个 Pass 对应 Low/Medium/High（每侧 2/3/4 次采样）。
Shader "Hidden/Universal Render Pipeline/CameraMotionBlur"
{
    SubShader
    {
        ZTest Always ZWrite Off Cull Off
        GLSLINCLUDE
        VARYING vec2 uv;
        #ifdef VERTEX
        void main()
        {
            vec2 p = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);
            uv = p;
            gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
        }
        #endif
        #include "URP/PostFXCommon.glsl"
        uniform mat4 _ViewProjM;
        uniform mat4 _PrevViewProjM;
        uniform float _Intensity;
        uniform float _Clamp;
        uniform vec4 _SourceSize;

        vec2 ClampVelocity(vec2 velocity, float maxVelocity)
        {
            float len = length(velocity);
            return (len > 0.0) ? min(len, maxVelocity) * (velocity / len) : vec2(0.0);
        }

        vec2 GetCameraVelocity(vec2 uv)
        {
            float depth = SampleSceneDepth(uv);   // WebGL 深度不反转（UNITY_REVERSED_Z = 0）
            vec3 worldPos = ComputeWorldSpacePosition(uv, depth, UNITY_MATRIX_I_VP);
            vec4 prevClipPos = _PrevViewProjM * vec4(worldPos, 1.0);
            vec4 curClipPos = _ViewProjM * vec4(worldPos, 1.0);
            vec2 prevPosCS = prevClipPos.xy / prevClipPos.w;
            vec2 curPosCS = curClipPos.xy / curClipPos.w;
            return ClampVelocity(prevPosCS - curPosCS, _Clamp);
        }

        vec3 GatherSample(float sampleNumber, vec2 velocity, float invSampleCount, vec2 centerUV, float randomVal, float velocitySign)
        {
            float offsetLength = (sampleNumber + 0.5) + (velocitySign * (randomVal - 0.5));
            vec2 sampleUV = centerUV + (offsetLength * invSampleCount) * velocity * velocitySign;
            // URP 用点采样
            return texelFetch(_BlitTexture, clamp(ivec2(sampleUV * _SourceSize.xy), ivec2(0), ivec2(_SourceSize.xy) - 1), 0).xyz;
        }

        vec4 DoMotionBlur(int iterations)
        {
            vec2 velocity = GetCameraVelocity(uv) * _Intensity;
            float randomVal = InterleavedGradientNoise(uv * _SourceSize.xy, 0);
            float invSampleCount = 1.0 / (float(iterations) * 2.0);
            vec3 color = vec3(0.0);
            for (int i = 0; i < iterations; i++)
            {
                color += GatherSample(float(i), velocity, invSampleCount, uv, randomVal, -1.0);
                color += GatherSample(float(i), velocity, invSampleCount, uv, randomVal, 1.0);
            }
            return vec4(color * invSampleCount, 1.0);
        }
        ENDGLSL

        Pass
        {
            Name "Camera Motion Blur - Low Quality"
            GLSLPROGRAM
            #ifdef FRAGMENT
            void main() { fragColor = DoMotionBlur(2); }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "Camera Motion Blur - Medium Quality"
            GLSLPROGRAM
            #ifdef FRAGMENT
            void main() { fragColor = DoMotionBlur(3); }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "Camera Motion Blur - High Quality"
            GLSLPROGRAM
            #ifdef FRAGMENT
            void main() { fragColor = DoMotionBlur(4); }
            #endif
            ENDGLSL
        }
    }
}
