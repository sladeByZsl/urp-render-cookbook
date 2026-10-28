// 第 9 章：白炉测试（White Furnace Test）。（GLSL 版，对应 Ch09/WhiteFurnace.shader）
// 假想物体被一个处处亮度相同的环境 L_env 包围，那么出射辐射率
//   L_o(v) = L_env · ∫ f(l,v) (n·l) dω_l = L_env · E(v)
// E(v) 就是 BRDF 的“方向反照率”。能量守恒要求 E ≤ 1；E = 1 时物体会和背景融为一体。
// 本 Shader 在每个像素上用蒙特卡洛积分直接算出 E(v)，不依赖任何灯光。
Shader "Cookbook/Ch09/WhiteFurnace"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        Pass
        {
            Name "Furnace"
            Tags { "LightMode"="UniversalForward" }

            GLSLPROGRAM
            #include "Ch09/BRDFLib.glsl"

            uniform float _Model, _Roughness, _Albedo, _SampleCount;
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
            vec3 TangentToWorld(vec3 d, vec3 N)
            {
                vec3 up = abs(N.y) < 0.999 ? vec3(0, 1, 0) : vec3(1, 0, 0);
                vec3 T = normalize(cross(up, N));
                vec3 B = cross(N, T);
                return T * d.x + B * d.y + N * d.z;
            }
            //#endregion

            //#region estimate
            float DirectionalAlbedo(vec3 N, vec3 V)
            {
                uint count = uint(_SampleCount);
                float NoV = max(dot(N, V), 1e-4);
                float a = _Roughness * _Roughness;
                float sum = 0.0;

                for (uint i = 0u; i < count; i++)
                {
                    vec2 xi = vec2((float(i) + 0.5) / float(count), RadicalInverse(i));

                    if (_Model < 0.5)
                    {
                        // Lambert：在半球上均匀采样，pdf = 1/(2π)
                        // 估计量 = f·cosθ / pdf = (ρ/π)·cosθ·2π
                        float cosT = xi.x, sinT = sqrt(1.0 - cosT * cosT), phi = TWO_PI * xi.y;
                        vec3 L = TangentToWorld(vec3(sinT * cos(phi), sinT * sin(phi), cosT), N);
                        sum += C9_Lambert(vec3(_Albedo)).x * saturate(dot(N, L)) * TWO_PI;
                    }
                    else
                    {
                        // GGX 重要性采样：按 D(h)(n·h) 的分布抽半程向量 h，再反射得到 l
                        // pdf(l) = D·(n·h) / (4 (v·h))，估计量化简为 G·F·(v·h) / ((n·v)(n·h))，这里 F = 1
                        float cosT = sqrt((1.0 - xi.x) / (1.0 + (a * a - 1.0) * xi.x));
                        float sinT = sqrt(1.0 - cosT * cosT), phi = TWO_PI * xi.y;
                        vec3 H = TangentToWorld(vec3(sinT * cos(phi), sinT * sin(phi), cosT), N);
                        vec3 L = reflect(-V, H);
                        float NoL = dot(N, L);
                        if (NoL > 0.0)
                        {
                            float NoH = saturate(dot(N, H)), VoH = saturate(dot(V, H));
                            float G = C9_G_SmithHeightCorrelated(NoL, NoV, a);
                            sum += G * VoH / (NoV * max(NoH, 1e-4));
                        }
                    }
                }
                return sum / float(count);
            }
            //#endregion

            void main()
            {
                vec3 N = normalize(normalWS);
                vec3 V = GetWorldSpaceNormalizeViewDir(positionWS);
                float E = DirectionalAlbedo(N, V);
                fragColor = vec4(_EnvColor.rgb * E, 1.0);
            }
            #endif
            ENDGLSL
        }
    }
}
