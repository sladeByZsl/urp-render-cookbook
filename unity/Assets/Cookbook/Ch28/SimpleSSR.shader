// 案例 28.6：最简屏幕空间反射（SSR）。世界空间线性步进 + 二分细化，命中后从屏幕颜色里取反射色。
// 只对“朝上”的表面生效（模拟湿地面），用 ScreenEffectFeature 驱动，需要 Depth + Normal。
Shader "Cookbook/Ch28/SimpleSSR"
{
    Properties
    {
        _MaxSteps ("Max Steps", Range(8, 128)) = 64
        _StepSize ("Step Size (m)", Float) = 0.12
        _Thickness ("Thickness (m)", Float) = 0.3
        _F0 ("Fresnel F0", Range(0, 1)) = 0.25
        _Intensity ("Intensity", Range(0, 1)) = 1
        _MinNormalY ("Min Normal Y", Range(0, 1)) = 0.8
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        ZWrite Off ZTest Always Cull Off Blend Off

        Pass
        {
            Name "SSR"
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #include "Assets/Cookbook/Ch28/ScreenSpaceCommon.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareNormalsTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Random.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float _MaxSteps, _StepSize, _Thickness, _F0, _Intensity, _MinNormalY;
            CBUFFER_END

            //#region trace
            // 光线上一点 → (屏幕 uv, 光线点自己的观察深度, 该处场景的观察深度)
            float3 ProjectRay(float3 p, out float2 uv)
            {
                uv = ComputeNormalizedDeviceCoordinates(p, UNITY_MATRIX_VP);
                float rayEye = LinearEyeDepth(p, UNITY_MATRIX_V);
                float sceneEye = LinearEyeDepth(SampleSceneDepthLod(uv), _ZBufferParams);
                return float3(uv, rayEye - sceneEye);   // z>0：光线跑到了场景表面后面
            }

            bool TraceReflection(float3 originWS, float3 dirWS, float jitter, out float2 hitUV, out float hitFade)
            {
                hitUV = 0; hitFade = 0;
                float3 prev = originWS;
                int steps = (int)_MaxSteps;
                for (int i = 1; i <= steps; i++)
                {
                    float3 p = originWS + dirWS * (_StepSize * (i + jitter));
                    float2 uv;
                    float diff = ProjectRay(p, uv).z;
                    if (any(uv < 0) || any(uv > 1)) return false;          // 走出屏幕：屏幕里没有信息了
                    if (diff > 0 && diff < _Thickness)                      // 穿过了一个“有厚度”的表面
                    {
                        // 二分细化：在 prev 与 p 之间逼近交点，减少台阶感
                        float3 a = prev, b = p;
                        for (int k = 0; k < 5; k++)
                        {
                            float3 m = (a + b) * 0.5;
                            float2 muv;
                            if (ProjectRay(m, muv).z > 0) b = m; else a = m;
                        }
                        ProjectRay(b, hitUV);
                        // 越靠屏幕边缘、越接近最大步数，越淡出，避免硬切
                        float2 edge = smoothstep(0, 0.08, hitUV) * smoothstep(1, 0.92, hitUV);
                        hitFade = edge.x * edge.y * (1 - (float)i / steps);
                        return true;
                    }
                    prev = p;
                }
                return false;
            }
            //#endregion

            //#region frag
            half4 Frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                float2 uv = input.texcoord;
                half4 color = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_PointClamp, uv);
                float depth = SampleDeviceDepth(uv);
                if (IsSkyDepth(depth)) return color;

                float3 normalWS = normalize(SampleSceneNormals(uv));
                if (normalWS.y < _MinNormalY) return color;               // 只让“地面”反射

                float3 positionWS = ReconstructPositionWS(uv, depth);
                float3 viewDirWS = normalize(positionWS - _WorldSpaceCameraPos);
                float3 reflDirWS = reflect(viewDirWS, normalWS);

                float jitter = InterleavedGradientNoise(input.positionCS.xy, 0);
                float2 hitUV; float fade;
                if (!TraceReflection(positionWS + normalWS * 0.02, reflDirWS, jitter, hitUV, fade))
                    return color;

                half3 reflColor = SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_LinearClamp, hitUV, 0).rgb;
                float NoV = saturate(dot(normalWS, -viewDirWS));
                float fresnel = _F0 + (1 - _F0) * pow(1 - NoV, 5);         // Schlick
                color.rgb = lerp(color.rgb, reflColor, saturate(fresnel * fade * _Intensity));
                return color;
            }
            //#endregion
            ENDHLSL
        }
    }
}
