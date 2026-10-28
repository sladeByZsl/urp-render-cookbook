// 案例 28.4：简化版 SSAO（法线半球采样 + 深度感知模糊）。
// Pass 0 AO：输出“可见度”（1 = 不被遮挡），与 URP 的 _ScreenSpaceOcclusionTexture 约定一致
// Pass 1/2：水平 / 竖直双边模糊；Pass 3：把 AO 乘到画面上；Pass 4：只显示 AO（调试）
Shader "Cookbook/Ch28/SimpleSSAO"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        ZWrite Off ZTest Always Cull Off Blend Off

        GLSLINCLUDE
        #include "Ch28/ScreenSpaceCommon.glsl"

        uniform float _Radius;
        uniform float _Intensity;
        uniform float _SampleCount;
        uniform float _Bias;
        uniform vec4 _SSAOTexelSize;      // C# 每帧设置：AO 纹理的 (1/w, 1/h, w, h)
        uniform sampler2D _SSAOResult;    // 合成时读取的 AO 结果

        float EyeDepthAt(vec2 uv) { return LinearEyeDepth(SampleSceneDepthLod(uv), _ZBufferParams); }
        // URP 的 LinearEyeDepth(positionWS, viewMatrix) 重载：观察空间 z 取反
        float LinearEyeDepthWS(vec3 positionWS) { return -(UNITY_MATRIX_V * vec4(positionWS, 1.0)).z; }
        // ComputeNormalizedDeviceCoordinates：世界坐标 → 屏幕 UV
        vec2 ComputeNormalizedDeviceCoordinates(vec3 positionWS, mat4 vp)
        {
            vec4 positionCS = vp * vec4(positionWS, 1.0);
            return positionCS.xy / positionCS.w * 0.5 + 0.5;
        }
        // Random.hlsl 的 InterleavedGradientNoise
        float InterleavedGradientNoise(vec2 pixCoord, int frameCount)
        {
            pixCoord += float(frameCount) * vec2(2.083, 4.867);
            return fract(52.9829189 * fract(dot(pixCoord, vec2(0.06711056, 0.00583715))));
        }

        //#region blur
        // 双边模糊：高斯权重 × 深度相似度权重，跨越深度断层的样本被压低，AO 不会渗到背景上
        vec4 BilateralBlur(vec2 uv, vec2 dir)
        {
            const float w[4] = float[4](0.324, 0.232, 0.0855, 0.0205);
            float centerEye = EyeDepthAt(uv);
            float sum = texture(_BlitTexture, uv).r * w[0];
            float wsum = w[0];
            for (int i = 1; i < 4; i++)
            {
                for (int s = -1; s <= 1; s += 2)
                {
                    vec2 suv = uv + dir * float(i * s);
                    float d = EyeDepthAt(suv);
                    float wd = w[i] * exp(-abs(d - centerEye) / max(centerEye * 0.02, 1e-3));
                    sum += textureLod(_BlitTexture, suv, 0.0).r * wd;
                    wsum += wd;
                }
            }
            float v = sum / wsum;
            return vec4(v, v, v, 1.0);
        }
        //#endregion
        ENDGLSL

        Pass
        {
            Name "AO"
            GLSLPROGRAM
            #ifdef FRAGMENT
            //#region ao
            vec4 FragAO()
            {
                vec2 uv = texcoord;
                float depth = SampleDeviceDepth(uv);
                if (IsSkyDepth(depth)) return vec4(1.0);

                vec3 positionWS = ReconstructPositionWS(uv, depth);
                vec3 normalWS = normalize(SampleSceneNormals(uv));   // URP 14 的法线纹理是世界空间
                float centerEye = LinearEyeDepthWS(positionWS);

                // 每像素一个随机旋转角，把规则的采样图案打散成高频噪声，后面再模糊掉
                float noise = InterleavedGradientNoise(gl_FragCoord.xy, 0);
                vec3 randomDir = vec3(cos(noise * TWO_PI), sin(noise * TWO_PI), 0.37);
                vec3 tangentWS = normalize(cross(normalWS, randomDir));
                vec3 bitangentWS = cross(normalWS, tangentWS);

                int count = int(_SampleCount);
                float occlusion = 0.0;
                for (int i = 0; i < count; i++)
                {
                    // 余弦分布的半球方向（黄金角螺旋），长度向中心聚集：近处样本更重要
                    float u = (float(i) + 0.5) / float(count);
                    float phi = float(i) * 2.39996323;
                    float cosTheta = sqrt(1.0 - u), sinTheta = sqrt(u);
                    vec3 dirTS = vec3(cos(phi) * sinTheta, sin(phi) * sinTheta, cosTheta);
                    float lenScale = mix(0.1, 1.0, fract(u * 7.31 + noise) * fract(u * 7.31 + noise));
                    vec3 offsetWS = (tangentWS * dirTS.x + bitangentWS * dirTS.y + normalWS * dirTS.z) * (lenScale * _Radius);
                    vec3 sampleWS = positionWS + offsetWS;

                    // 投影回屏幕，读那里的场景深度
                    vec2 sampleUV = ComputeNormalizedDeviceCoordinates(sampleWS, UNITY_MATRIX_VP);
                    float sampleEye = LinearEyeDepthWS(sampleWS);
                    float sceneEye = EyeDepthAt(sampleUV);

                    // 场景表面在样本点前面 → 样本点被埋住 → 记一次遮挡
                    float occluded = sceneEye < sampleEye - _Bias ? 1.0 : 0.0;
                    // 范围检查：深度差远大于半径的（背景前的前景边缘）不算，避免黑边光晕
                    float rangeCheck = smoothstep(0.0, 1.0, _Radius / max(abs(centerEye - sceneEye), 1e-4));
                    occlusion += occluded * rangeCheck;
                }
                float visibility = saturate(1.0 - occlusion / float(count) * _Intensity);
                return vec4(visibility, visibility, visibility, 1.0);
            }
            //#endregion
            void main() { fragColor = FragAO(); }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "BlurH"
            GLSLPROGRAM
            #ifdef FRAGMENT
            void main() { fragColor = BilateralBlur(texcoord, vec2(_SSAOTexelSize.x, 0.0)); }
            #endif
            ENDGLSL
        }
        Pass
        {
            Name "BlurV"
            GLSLPROGRAM
            #ifdef FRAGMENT
            void main() { fragColor = BilateralBlur(texcoord, vec2(0.0, _SSAOTexelSize.y)); }
            #endif
            ENDGLSL
        }
        Pass
        {
            Name "CompositeMultiply"
            GLSLPROGRAM
            #ifdef FRAGMENT
            void main()
            {
                vec4 color = SamplePointClamp(_BlitTexture, texcoord);
                float ao = texture(_SSAOResult, texcoord).r;
                fragColor = vec4(color.rgb * ao, color.a);
            }
            #endif
            ENDGLSL
        }
        Pass
        {
            Name "ShowAO"
            GLSLPROGRAM
            #ifdef FRAGMENT
            void main()
            {
                float ao = texture(_SSAOResult, texcoord).r;
                fragColor = vec4(ao, ao, ao, 1.0);
            }
            #endif
            ENDGLSL
        }
    }
}
