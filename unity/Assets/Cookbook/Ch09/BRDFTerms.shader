// 第 9 章：BRDF 单项可视化。
// 用一个 _Mode 参数切换输出 D、G、F、镜面项、漫反射项或完整的直接光照，
// 配合一排粗糙度递增的小球，就能“看见”每一项随粗糙度怎么变。
Shader "Cookbook/Ch09/BRDFTerms"
{
    Properties
    {
        [Enum(D,0,G,1,F_NoV,2,F_VoH,3,Specular,4,Diffuse,5,Full,6)] _Mode("Output", Float) = 6
        [Enum(GGX,0,Beckmann,1,BlinnPhong,2)] _NDF("NDF", Float) = 0
        [Enum(SmithSeparable,0,SmithHeightCorrelated,1,SchlickGGX,2,DiffX10,3)] _GModel("Geometry", Float) = 1
        [Enum(Lambert,0,Disney,1)] _DiffuseModel("Diffuse", Float) = 0
        _Roughness("Perceptual Roughness", Range(0.02, 1)) = 0.5
        _F0("F0 (linear)", Color) = (0.04, 0.04, 0.04, 1)
        _Albedo("Diffuse Albedo", Color) = (0.8, 0.8, 0.8, 1)
        [Enum(Raw,0,Exp,1)] _Display("Display", Float) = 0
        _Exposure("Exposure", Float) = 1
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Assets/Cookbook/Ch09/BRDFLib.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float _Mode, _NDF, _GModel, _DiffuseModel;
                float _Roughness;
                float4 _F0, _Albedo;
                float _Display, _Exposure;
            CBUFFER_END

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; };
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float3 normalWS   : TEXCOORD1;
            };

            Varyings vert(Attributes v)
            {
                Varyings o;
                VertexPositionInputs p = GetVertexPositionInputs(v.positionOS.xyz);
                o.positionCS = p.positionCS;
                o.positionWS = p.positionWS;
                o.normalWS = TransformObjectToWorldNormal(v.normalOS);
                return o;
            }

            //#region terms
            float EvalD(float NoH, float a)
            {
                if (_NDF < 0.5) return C9_D_GGX(NoH, a);
                if (_NDF < 1.5) return C9_D_Beckmann(NoH, a);
                return C9_D_BlinnPhong(NoH, a);
            }

            float EvalG(float NoL, float NoV, float a)
            {
                if (_GModel < 0.5) return C9_G_SmithSeparable(NoL, NoV, a);
                if (_GModel < 1.5) return C9_G_SmithHeightCorrelated(NoL, NoV, a);
                if (_GModel < 2.5) return C9_G_SchlickGGX(NoL, NoV, a);
                // 两种 Smith 形式之差放大 10 倍，看它们在哪儿不一样
                return abs(C9_G_SmithHeightCorrelated(NoL, NoV, a) - C9_G_SmithSeparable(NoL, NoV, a)) * 10.0;
            }
            //#endregion

            half4 frag(Varyings i) : SV_Target
            {
                //#region frag
                float3 N = normalize(i.normalWS);
                float3 V = GetWorldSpaceNormalizeViewDir(i.positionWS);
                Light light = GetMainLight();
                float3 L = light.direction;
                float3 H = SafeNormalize(L + V);

                float NoL = saturate(dot(N, L));
                float NoV = max(dot(N, V), 1e-4);     // 防止边缘处除零
                float NoH = saturate(dot(N, H));
                float VoH = saturate(dot(V, H));
                float LoH = VoH;                       // h 是 l、v 的角平分线，两者相等

                float a = _Roughness * _Roughness;     // α = perceptualRoughness²

                float  D = EvalD(NoH, a);
                float  G = EvalG(NoL, NoV, a);
                float3 F = C9_F_Schlick(_F0.rgb, VoH);

                // Cook-Torrance 镜面 BRDF：D·G·F / (4 (n·l)(n·v))
                float3 fSpec = D * G * F / max(4.0 * NoL * NoV, 1e-4);
                float3 fDiff = (_DiffuseModel < 0.5)
                    ? C9_Lambert(_Albedo.rgb)
                    : C9_DisneyDiffuse(_Albedo.rgb, NoL, NoV, LoH, _Roughness);

                // Unity 的灯光“颜色×强度”约定：白色 Lambert 面正对强度 1 的灯时输出 1，
                // 相当于入射辐照度 E = π · lightColor，所以出射辐射率 = f · π · lightColor · (n·l)。
                float3 E = PI * light.color * NoL;

                float3 c;
                if      (_Mode < 0.5) c = D.xxx;
                else if (_Mode < 1.5) c = (NoL > 0.0 ? G : 0.0).xxx;
                else if (_Mode < 2.5) c = C9_F_Schlick(_F0.rgb, NoV);
                else if (_Mode < 3.5) c = F;
                else if (_Mode < 4.5) c = fSpec * E;
                else if (_Mode < 5.5) c = fDiff * E;
                else                  c = ((1.0 - F) * fDiff + fSpec) * E;   // 漫反射只拿“没被镜面反射走”的那部分

                // 显示映射：Raw 直接输出（超过 1 会被截断）；Exp 用 1 - e^(-x·k) 把大范围数值压进 0..1
                if (_Display > 0.5) c = 1.0 - exp(-c * _Exposure);
                else                c *= _Exposure;
                return half4(c, 1);
                //#endregion
            }
            ENDHLSL
        }
    }
}
