// 案例 28.6：最简屏幕空间反射（SSR）。世界空间线性步进 + 二分细化，命中后从屏幕颜色里取反射色。
// 只对“朝上”的表面生效（模拟湿地面），用 ScreenEffectFeature 驱动，需要 Depth + Normal。
Shader "Cookbook/Ch28/SimpleSSR"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        ZWrite Off ZTest Always Cull Off Blend Off

        Pass
        {
            Name "SSR"
            GLSLPROGRAM
            #include "Ch28/ScreenSpaceCommon.glsl"

            uniform float _MaxSteps, _StepSize, _Thickness, _F0, _Intensity, _MinNormalY;

            #ifdef FRAGMENT
            float InterleavedGradientNoise(vec2 pixCoord, int frameCount)
            {
                pixCoord += float(frameCount) * vec2(2.083, 4.867);
                return fract(52.9829189 * fract(dot(pixCoord, vec2(0.06711056, 0.00583715))));
            }

            //#region trace
            // 光线上一点 → (屏幕 uv, 光线点自己的观察深度 - 该处场景的观察深度)
            vec3 ProjectRay(vec3 p, out vec2 uv)
            {
                vec4 cs = UNITY_MATRIX_VP * vec4(p, 1.0);       // ComputeNormalizedDeviceCoordinates
                uv = cs.xy / cs.w * 0.5 + 0.5;
                float rayEye = -(UNITY_MATRIX_V * vec4(p, 1.0)).z;  // LinearEyeDepth(p, UNITY_MATRIX_V)
                float sceneEye = LinearEyeDepth(SampleSceneDepthLod(uv), _ZBufferParams);
                return vec3(uv, rayEye - sceneEye);   // z>0：光线跑到了场景表面后面
            }

            bool TraceReflection(vec3 originWS, vec3 dirWS, float jitter, out vec2 hitUV, out float hitFade)
            {
                hitUV = vec2(0.0); hitFade = 0.0;
                vec3 prev = originWS;
                int steps = int(_MaxSteps);
                for (int i = 1; i <= steps; i++)
                {
                    vec3 p = originWS + dirWS * (_StepSize * (float(i) + jitter));
                    vec2 uv;
                    float diff = ProjectRay(p, uv).z;
                    if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) return false;  // 走出屏幕：屏幕里没有信息了
                    if (diff > 0.0 && diff < _Thickness)                    // 穿过了一个“有厚度”的表面
                    {
                        // 二分细化：在 prev 与 p 之间逼近交点，减少台阶感
                        vec3 a = prev, b = p;
                        for (int k = 0; k < 5; k++)
                        {
                            vec3 m = (a + b) * 0.5;
                            vec2 muv;
                            if (ProjectRay(m, muv).z > 0.0) b = m; else a = m;
                        }
                        ProjectRay(b, hitUV);
                        // 越靠屏幕边缘、越接近最大步数，越淡出，避免硬切
                        vec2 edge = smoothstep(0.0, 0.08, hitUV) * smoothstep(1.0, 0.92, hitUV);
                        hitFade = edge.x * edge.y * (1.0 - float(i) / float(steps));
                        return true;
                    }
                    prev = p;
                }
                return false;
            }
            //#endregion

            //#region frag
            vec4 Frag()
            {
                vec2 uv = texcoord;
                vec4 color = SamplePointClamp(_BlitTexture, uv);
                float depth = SampleDeviceDepth(uv);
                if (IsSkyDepth(depth)) return color;

                vec3 normalWS = normalize(SampleSceneNormals(uv));
                if (normalWS.y < _MinNormalY) return color;               // 只让“地面”反射

                vec3 positionWS = ReconstructPositionWS(uv, depth);
                vec3 viewDirWS = normalize(positionWS - _WorldSpaceCameraPos);
                vec3 reflDirWS = reflect(viewDirWS, normalWS);

                float jitter = InterleavedGradientNoise(gl_FragCoord.xy, 0);
                vec2 hitUV; float fade;
                if (!TraceReflection(positionWS + normalWS * 0.02, reflDirWS, jitter, hitUV, fade))
                    return color;

                vec3 reflColor = textureLod(_BlitTexture, hitUV, 0.0).rgb;
                float NoV = saturate(dot(normalWS, -viewDirWS));
                float fresnel = _F0 + (1.0 - _F0) * pow(1.0 - NoV, 5.0);         // Schlick
                color.rgb = mix(color.rgb, reflColor, saturate(fresnel * fade * _Intensity));
                return color;
            }
            //#endregion
            void main() { fragColor = Frag(); }
            #endif
            ENDGLSL
        }
    }
}
