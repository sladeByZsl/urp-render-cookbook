// 第 10 章：URP 的 DirectBRDFSpecular（移动端近似）vs 标准 GGX · 高度相关 Smith · Schlick。（GLSL 版，对应 Ch10/SpecCompare.shader）
// 只输出主光的直接高光，参照组完全用 core 包 BSDF.hlsl 里的标准函数（网页版抄在 Ch10/CoreBSDF.glsl）。
Shader "Cookbook/Ch10/SpecCompare"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }
        Pass
        {
            Tags { "LightMode"="UniversalForward" }
            GLSLPROGRAM
            #include "Ch10/CoreBSDF.glsl"

            uniform float _Mode, _Smoothness, _Exposure;
            uniform vec4 _F0;

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
            //#region frag
            void main()
            {
                vec3 N = normalize(normalWS);
                vec3 V = GetWorldSpaceNormalizeViewDir(positionWS);
                Light light = GetMainLight();
                vec3 L = light.direction;
                float NoL = saturate(dot(N, L));

                // 用 URP 自己的初始化：金属度 1、albedo = F0，于是 brdf.specular = F0、brdf.diffuse = 0
                float alpha = 1.0;
                BRDFData brdf;
                InitializeBRDFData(_F0.rgb, 1.0, vec3(0.0), _Smoothness, alpha, brdf);

                vec3 spec;   // 已经乘了 π 的“Unity 约定”镜面项，乘 lightColor·NoL 即出射辐射率
                if (_Mode < 0.5)
                {
                    spec = brdf.specular * DirectBRDFSpecular(brdf, N, L, V);
                }
                else
                {
                    vec3 H = SafeNormalize(L + V);
                    float NoV = max(dot(N, V), 1e-4), NoH = saturate(dot(N, H)), VoH = saturate(dot(V, H));
                    float a = brdf.roughness;                                   // α，与 URP 用同一个值
                    float DV = D_GGX(NoH, a) * V_SmithJointGGX(NoL, NoV, a);    // core/BSDF.hlsl
                    spec = PI * DV * F_Schlick(_F0.rgb, VoH);
                }

                vec3 c = spec * light.color * NoL;
                fragColor = vec4(1.0 - exp(-c * _Exposure), 1.0);
            }
            //#endregion
            #endif
            ENDGLSL
        }
    }
}
