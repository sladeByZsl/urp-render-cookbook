// 案例 28.4：简化版 SSAO（法线半球采样 + 深度感知模糊）。
// Pass 0 AO：输出“可见度”（1 = 不被遮挡），与 URP 的 _ScreenSpaceOcclusionTexture 约定一致
// Pass 1/2：水平 / 竖直双边模糊；Pass 3：把 AO 乘到画面上；Pass 4：只显示 AO（调试）
Shader "Cookbook/Ch28/SimpleSSAO"
{
    Properties
    {
        _Radius ("Radius (m)", Float) = 0.5
        _Intensity ("Intensity", Float) = 1.2
        _SampleCount ("Sample Count", Range(4, 32)) = 16
        _Bias ("Depth Bias (m)", Float) = 0.02
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        ZWrite Off ZTest Always Cull Off Blend Off

        HLSLINCLUDE
        #include "Assets/Cookbook/Ch28/ScreenSpaceCommon.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareNormalsTexture.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Random.hlsl"

        CBUFFER_START(UnityPerMaterial)
            float _Radius, _Intensity, _SampleCount, _Bias;
        CBUFFER_END
        float4 _SSAOTexelSize;     // C# 每帧设置：AO 纹理的 (1/w, 1/h, w, h)
        TEXTURE2D_X(_SSAOResult);  // 合成时读取的 AO 结果

        float EyeDepthAt(float2 uv) { return LinearEyeDepth(SampleSceneDepthLod(uv), _ZBufferParams); }

        //#region blur
        // 双边模糊：高斯权重 × 深度相似度权重，跨越深度断层的样本被压低，AO 不会渗到背景上
        half4 BilateralBlur(float2 uv, float2 dir)
        {
            static const float w[4] = { 0.324, 0.232, 0.0855, 0.0205 };
            float centerEye = EyeDepthAt(uv);
            half sum = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv).r * w[0];
            float wsum = w[0];
            for (int i = 1; i < 4; i++)
            {
                for (int s = -1; s <= 1; s += 2)
                {
                    float2 suv = uv + dir * (i * s);
                    float d = EyeDepthAt(suv);
                    float wd = w[i] * exp(-abs(d - centerEye) / max(centerEye * 0.02, 1e-3));
                    sum += SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_LinearClamp, suv, 0).r * wd;
                    wsum += wd;
                }
            }
            half v = sum / wsum;
            return half4(v, v, v, 1);
        }
        //#endregion
        ENDHLSL

        Pass
        {
            Name "AO"
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment FragAO
            //#region ao
            half4 FragAO(Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                float2 uv = input.texcoord;
                float depth = SampleDeviceDepth(uv);
                if (IsSkyDepth(depth)) return 1;

                float3 positionWS = ReconstructPositionWS(uv, depth);
                float3 normalWS = normalize(SampleSceneNormals(uv));   // URP 14 的法线纹理是世界空间
                float centerEye = LinearEyeDepth(positionWS, UNITY_MATRIX_V);

                // 每像素一个随机旋转角，把规则的采样图案打散成高频噪声，后面再模糊掉
                float noise = InterleavedGradientNoise(input.positionCS.xy, 0);
                float3 randomDir = float3(cos(noise * TWO_PI), sin(noise * TWO_PI), 0.37);
                float3 tangentWS = normalize(cross(normalWS, randomDir));
                float3 bitangentWS = cross(normalWS, tangentWS);

                int count = (int)_SampleCount;
                float occlusion = 0;
                for (int i = 0; i < count; i++)
                {
                    // 余弦分布的半球方向（黄金角螺旋），长度向中心聚集：近处样本更重要
                    float u = (i + 0.5) / count;
                    float phi = i * 2.39996323;
                    float cosTheta = sqrt(1 - u), sinTheta = sqrt(u);
                    float3 dirTS = float3(cos(phi) * sinTheta, sin(phi) * sinTheta, cosTheta);
                    float lenScale = lerp(0.1, 1.0, frac(u * 7.31 + noise) * frac(u * 7.31 + noise));
                    float3 offsetWS = (tangentWS * dirTS.x + bitangentWS * dirTS.y + normalWS * dirTS.z) * (lenScale * _Radius);
                    float3 sampleWS = positionWS + offsetWS;

                    // 投影回屏幕，读那里的场景深度
                    float2 sampleUV = ComputeNormalizedDeviceCoordinates(sampleWS, UNITY_MATRIX_VP);
                    float sampleEye = LinearEyeDepth(sampleWS, UNITY_MATRIX_V);
                    float sceneEye = EyeDepthAt(sampleUV);

                    // 场景表面在样本点前面 → 样本点被埋住 → 记一次遮挡
                    float occluded = sceneEye < sampleEye - _Bias ? 1 : 0;
                    // 范围检查：深度差远大于半径的（背景前的前景边缘）不算，避免黑边光晕
                    float rangeCheck = smoothstep(0, 1, _Radius / max(abs(centerEye - sceneEye), 1e-4));
                    occlusion += occluded * rangeCheck;
                }
                float visibility = saturate(1 - occlusion / count * _Intensity);
                return half4(visibility, visibility, visibility, 1);
            }
            //#endregion
            ENDHLSL
        }

        Pass
        {
            Name "BlurH"
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            half4 Frag(Varyings input) : SV_Target { return BilateralBlur(input.texcoord, float2(_SSAOTexelSize.x, 0)); }
            ENDHLSL
        }
        Pass
        {
            Name "BlurV"
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            half4 Frag(Varyings input) : SV_Target { return BilateralBlur(input.texcoord, float2(0, _SSAOTexelSize.y)); }
            ENDHLSL
        }
        Pass
        {
            Name "CompositeMultiply"
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            half4 Frag(Varyings input) : SV_Target
            {
                half4 color = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_PointClamp, input.texcoord);
                half ao = SAMPLE_TEXTURE2D_X(_SSAOResult, sampler_LinearClamp, input.texcoord).r;
                return half4(color.rgb * ao, color.a);
            }
            ENDHLSL
        }
        Pass
        {
            Name "ShowAO"
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            half4 Frag(Varyings input) : SV_Target
            {
                half ao = SAMPLE_TEXTURE2D_X(_SSAOResult, sampler_LinearClamp, input.texcoord).r;
                return half4(ao, ao, ao, 1);
            }
            ENDHLSL
        }
    }
}
