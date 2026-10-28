// 第 10 章：对 URP 直接高光做白炉测试。
// 与第 9 章的 WhiteFurnace 相同的蒙特卡洛积分，但被积的 BRDF 换成 URP 的 DirectBRDFSpecular（F0 = 1）。
// 能量守恒的 BRDF 积分结果 E ≤ 1；球比背景亮，说明这个近似在该粗糙度下“造”出了能量。
Shader "Cookbook/Ch10/SpecFurnace"
{
    Properties
    {
        [Enum(URP_Approx,0,Reference,1)] _Mode("Mode", Float) = 0
        _Smoothness("Smoothness", Range(0, 1)) = 0.5
        _EnvColor("Environment Radiance", Color) = (0.5, 0.5, 0.5, 1)
        _SampleCount("Sample Count", Float) = 1024
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }
        Pass
        {
            Tags { "LightMode"="UniversalForward" }
            HLSLPROGRAM
            #pragma target 4.5
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float _Mode, _Smoothness, _SampleCount;
                float4 _EnvColor;
            CBUFFER_END

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; };
            struct Varyings { float4 positionCS : SV_POSITION; float3 positionWS : TEXCOORD0; float3 normalWS : TEXCOORD1; };

            Varyings vert(Attributes v)
            {
                Varyings o;
                o.positionWS = TransformObjectToWorld(v.positionOS.xyz);
                o.positionCS = TransformWorldToHClip(o.positionWS);
                o.normalWS = TransformObjectToWorldNormal(v.normalOS);
                return o;
            }

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
            half4 frag(Varyings i) : SV_Target
            {
                float3 N = normalize(i.normalWS);
                float3 V = GetWorldSpaceNormalizeViewDir(i.positionWS);
                float NoV = max(dot(N, V), 1e-4);

                half alpha = 1;
                BRDFData brdf;
                InitializeBRDFData(half3(1, 1, 1), 1.0, 0, _Smoothness, alpha, brdf);   // F0 = 1
                float a = brdf.roughness;

                float3 up = abs(N.y) < 0.999 ? float3(0, 1, 0) : float3(1, 0, 0);
                float3 T = normalize(cross(up, N)), B = cross(N, T);

                uint count = (uint)_SampleCount;
                float sum = 0;
                for (uint k = 0; k < count; k++)
                {
                    float2 xi = float2((k + 0.5) / count, RadicalInverse(k));
                    float cosT = sqrt((1 - xi.x) / (1 + (a * a - 1) * xi.x));
                    float sinT = sqrt(1 - cosT * cosT), phi = TWO_PI * xi.y;
                    float3 H = T * (sinT * cos(phi)) + B * (sinT * sin(phi)) + N * cosT;
                    float3 L = reflect(-V, H);
                    float NoL = dot(N, L);
                    if (NoL <= 0) continue;
                    float NoH = saturate(dot(N, H)), VoH = saturate(dot(V, H));

                    float pdf = D_GGX(NoH, a) * NoH / (4 * VoH);                       // 按 GGX 抽样的概率密度
                    float f = (_Mode < 0.5)
                        ? DirectBRDFSpecular(brdf, N, L, V) * INV_PI                   // 去掉 Unity 约定里的 π，还原成 BRDF
                        : D_GGX(NoH, a) * V_SmithJointGGX(NoL, NoV, a);                // F = 1
                    sum += f * NoL / max(pdf, 1e-6);
                }
                float E = sum / count;
                return half4(_EnvColor.rgb * E, 1);
            }
            //#endregion
            ENDHLSL
        }
    }
}
