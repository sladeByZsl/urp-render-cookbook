// 第 9 章：白炉测试（White Furnace Test）。
// 假想物体被一个处处亮度相同的环境 L_env 包围，那么出射辐射率
//   L_o(v) = L_env · ∫ f(l,v) (n·l) dω_l = L_env · E(v)
// E(v) 就是 BRDF 的“方向反照率”。能量守恒要求 E ≤ 1；E = 1 时物体会和背景融为一体。
// 本 Shader 在每个像素上用蒙特卡洛积分直接算出 E(v)，不依赖任何灯光。
Shader "Cookbook/Ch09/WhiteFurnace"
{
    Properties
    {
        [Enum(Lambert,0,GGX_Specular_F1,1)] _Model("BRDF", Float) = 0
        _Roughness("Perceptual Roughness", Range(0.02, 1)) = 0.5
        _Albedo("Albedo", Range(0, 1)) = 1
        _EnvColor("Environment Radiance", Color) = (0.5, 0.5, 0.5, 1)
        _SampleCount("Sample Count", Float) = 512
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        Pass
        {
            Name "Furnace"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma target 4.5
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Assets/Cookbook/Ch09/BRDFLib.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float _Model, _Roughness, _Albedo, _SampleCount;
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

            //#region sampling
            // Hammersley 低差异序列：第二维是 i 的二进制位反转（Van der Corput 序列）
            float RadicalInverse(uint bits)
            {
                bits = (bits << 16u) | (bits >> 16u);
                bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAAu) >> 1u);
                bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);
                bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);
                bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);
                return float(bits) * 2.3283064365386963e-10; // / 2^32
            }

            // 把切线空间方向转到以 N 为 z 轴的世界空间
            float3 TangentToWorld(float3 d, float3 N)
            {
                float3 up = abs(N.y) < 0.999 ? float3(0, 1, 0) : float3(1, 0, 0);
                float3 T = normalize(cross(up, N));
                float3 B = cross(N, T);
                return T * d.x + B * d.y + N * d.z;
            }
            //#endregion

            //#region estimate
            float DirectionalAlbedo(float3 N, float3 V)
            {
                uint count = (uint)_SampleCount;
                float NoV = max(dot(N, V), 1e-4);
                float a = _Roughness * _Roughness;
                float sum = 0;

                for (uint i = 0; i < count; i++)
                {
                    float2 xi = float2((i + 0.5) / count, RadicalInverse(i));

                    if (_Model < 0.5)
                    {
                        // Lambert：在半球上均匀采样，pdf = 1/(2π)
                        // 估计量 = f·cosθ / pdf = (ρ/π)·cosθ·2π
                        float cosT = xi.x, sinT = sqrt(1 - cosT * cosT), phi = TWO_PI * xi.y;
                        float3 L = TangentToWorld(float3(sinT * cos(phi), sinT * sin(phi), cosT), N);
                        sum += C9_Lambert(_Albedo.xxx).x * saturate(dot(N, L)) * TWO_PI;
                    }
                    else
                    {
                        // GGX 重要性采样：按 D(h)(n·h) 的分布抽半程向量 h，再反射得到 l
                        // pdf(l) = D·(n·h) / (4 (v·h))，估计量化简为 G·F·(v·h) / ((n·v)(n·h))，这里 F = 1
                        float cosT = sqrt((1 - xi.x) / (1 + (a * a - 1) * xi.x));
                        float sinT = sqrt(1 - cosT * cosT), phi = TWO_PI * xi.y;
                        float3 H = TangentToWorld(float3(sinT * cos(phi), sinT * sin(phi), cosT), N);
                        float3 L = reflect(-V, H);
                        float NoL = dot(N, L);
                        if (NoL > 0)
                        {
                            float NoH = saturate(dot(N, H)), VoH = saturate(dot(V, H));
                            float G = C9_G_SmithHeightCorrelated(NoL, NoV, a);
                            sum += G * VoH / (NoV * max(NoH, 1e-4));
                        }
                    }
                }
                return sum / count;
            }
            //#endregion

            half4 frag(Varyings i) : SV_Target
            {
                float3 N = normalize(i.normalWS);
                float3 V = GetWorldSpaceNormalizeViewDir(i.positionWS);
                float E = DirectionalAlbedo(N, V);
                return half4(_EnvColor.rgb * E, 1);
            }
            ENDHLSL
        }
    }
}
