// 第 10 章：URP 的 DirectBRDFSpecular（移动端近似）vs 标准 GGX · 高度相关 Smith · Schlick。
// 只输出主光的直接高光，参照组完全用 core 包 BSDF.hlsl 里的标准函数。
Shader "Cookbook/Ch10/SpecCompare"
{
    Properties
    {
        [Enum(URP_Approx,0,Reference,1)] _Mode("Mode", Float) = 0
        _Smoothness("Smoothness", Range(0, 1)) = 0.5
        _F0("F0 (linear)", Vector) = (0.9, 0.9, 0.9, 0)
        _Exposure("Exposure", Float) = 1
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }
        Pass
        {
            Tags { "LightMode"="UniversalForward" }
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float _Mode, _Smoothness, _Exposure;
                float4 _F0;
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

            //#region frag
            half4 frag(Varyings i) : SV_Target
            {
                float3 N = normalize(i.normalWS);
                float3 V = GetWorldSpaceNormalizeViewDir(i.positionWS);
                Light light = GetMainLight();
                float3 L = light.direction;
                float NoL = saturate(dot(N, L));

                // 用 URP 自己的初始化：金属度 1、albedo = F0，于是 brdf.specular = F0、brdf.diffuse = 0
                half alpha = 1;
                BRDFData brdf;
                InitializeBRDFData(_F0.rgb, 1.0, 0, _Smoothness, alpha, brdf);

                float3 spec;   // 已经乘了 π 的“Unity 约定”镜面项，乘 lightColor·NoL 即出射辐射率
                if (_Mode < 0.5)
                {
                    spec = brdf.specular * DirectBRDFSpecular(brdf, N, L, V);
                }
                else
                {
                    float3 H = SafeNormalize(L + V);
                    float NoV = max(dot(N, V), 1e-4), NoH = saturate(dot(N, H)), VoH = saturate(dot(V, H));
                    float a = brdf.roughness;                                   // α，与 URP 用同一个值
                    float DV = D_GGX(NoH, a) * V_SmithJointGGX(NoL, NoV, a);    // core/BSDF.hlsl
                    spec = PI * DV * F_Schlick(_F0.rgb, VoH);
                }

                float3 c = spec * light.color * NoL;
                return half4(1.0 - exp(-c * _Exposure), 1);
            }
            //#endregion
            ENDHLSL
        }
    }
}
