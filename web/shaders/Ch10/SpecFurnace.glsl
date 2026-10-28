// 第 10 章：对 URP 直接高光做白炉测试。（GLSL 版，对应 Ch10/SpecFurnace.shader）
// 与第 9 章的 WhiteFurnace 相同的蒙特卡洛积分，但被积的 BRDF 换成 URP 的 DirectBRDFSpecular（F0 = 1）。
// 能量守恒的 BRDF 积分结果 E ≤ 1；球比背景亮，说明这个近似在该粗糙度下“造”出了能量。
Shader "Cookbook/Ch10/SpecFurnace"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }
        Pass
        {
            Tags { "LightMode"="UniversalForward" }
            GLSLPROGRAM
            #include "Ch10/CoreBSDF.glsl"

            uniform float _Mode, _Smoothness, _SampleCount;
            uniform vec4 _EnvColor;

            VARYING vec3 positionWS;
            VARYING vec3 normalWS;

            #ifdef VERTEX
            void main()
            {
                positionWS = TransformObjectToWorld(positionOS.xyz);
                gl_Position = TransformWorldToHClip(positionWS);
                normalWS = TransformObjectToWorldNormal(normalOS);
            }
            #endif

            #ifdef FRAGMENT
            float RadicalInverse(uint bits)
            {
                bits = (bits << 16u) | (bits >> 16u);
                bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAAu) >> 1u);
                bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);
                bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);
                bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);
                return float(bits) * 2.3283064365386963e-10;
            }

            //#region estimate
            void main()
            {
                vec3 N = normalize(normalWS);
                vec3 V = GetWorldSpaceNormalizeViewDir(positionWS);
                float NoV = max(dot(N, V), 1e-4);

                float alpha = 1.0;
                BRDFData brdf;
                InitializeBRDFData(vec3(1.0), 1.0, vec3(0.0), _Smoothness, alpha, brdf);   // F0 = 1
                float a = brdf.roughness;

                vec3 up = abs(N.y) < 0.999 ? vec3(0, 1, 0) : vec3(1, 0, 0);
                vec3 T = normalize(cross(up, N)), B = cross(N, T);

                uint count = uint(_SampleCount);
                float sum = 0.0;
                for (uint k = 0u; k < count; k++)
                {
                    vec2 xi = vec2((float(k) + 0.5) / float(count), RadicalInverse(k));
                    float cosT = sqrt((1.0 - xi.x) / (1.0 + (a * a - 1.0) * xi.x));
                    float sinT = sqrt(1.0 - cosT * cosT), phi = TWO_PI * xi.y;
                    vec3 H = T * (sinT * cos(phi)) + B * (sinT * sin(phi)) + N * cosT;
                    vec3 L = reflect(-V, H);
                    float NoL = dot(N, L);
                    if (NoL <= 0.0) continue;
                    float NoH = saturate(dot(N, H)), VoH = saturate(dot(V, H));

                    float pdf = D_GGX(NoH, a) * NoH / (4.0 * VoH);                     // 按 GGX 抽样的概率密度
                    float f = (_Mode < 0.5)
                        ? DirectBRDFSpecular(brdf, N, L, V) * INV_PI                   // 去掉 Unity 约定里的 π，还原成 BRDF
                        : D_GGX(NoH, a) * V_SmithJointGGX(NoL, NoV, a);                // F = 1
                    sum += f * NoL / max(pdf, 1e-6);
                }
                float E = sum / float(count);
                fragColor = vec4(_EnvColor.rgb * E, 1.0);
            }
            //#endregion
            #endif
            ENDGLSL
        }
    }
}
