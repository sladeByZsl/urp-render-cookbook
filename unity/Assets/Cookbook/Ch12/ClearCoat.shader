// 清漆（Clear Coat）：在基础 GGX 材质上再盖一层透明的电介质 GGX。
// 两层之间的能量分配、折射对底层的影响，是本案例要讲清的重点。
Shader "Cookbook/Ch12/ClearCoat"
{
    Properties
    {
        [MainColor] _BaseColor ("Base Color", Color) = (0.6, 0.04, 0.03, 1)
        _Metallic ("Metallic", Range(0, 1)) = 0.6
        _Smoothness ("Base Smoothness", Range(0, 1)) = 0.45
        [Header(Flakes)]
        _FlakeDensity ("Flake Density (cells per UV)", Float) = 600
        _FlakeStrength ("Flake Normal Strength", Range(0, 1)) = 0.35
        [Header(Clear Coat)]
        _CoatMask ("Coat Mask", Range(0, 1)) = 1
        _CoatSmoothness ("Coat Smoothness", Range(0, 1)) = 0.95
        [Toggle] _CoatEnergy ("Energy Attenuation (1 - Fc)", Float) = 1
        [Toggle] _CoatAffectBase ("Coat Modifies Base (IOR 1.5)", Float) = 1
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
        CBUFFER_START(UnityPerMaterial)
            half4 _BaseColor;
            half  _Metallic, _Smoothness;
            float _FlakeDensity;
            half  _FlakeStrength;
            half  _CoatMask, _CoatSmoothness, _CoatEnergy, _CoatAffectBase;
        CBUFFER_END
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex Ch12Vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BLENDING
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BOX_PROJECTION
            #pragma multi_compile_fragment _ _LIGHT_COOKIES
            #pragma multi_compile _ _FORWARD_PLUS
            #pragma multi_compile_fog
            #pragma multi_compile_instancing

            #include "Assets/Cookbook/Ch12/Ch12Common.hlsl"

            //#region ctx
            struct MaterialCtx
            {
                float3 N, V;
                float3 flakeN;      // 带金属片扰动的底层法线
                float3 diffuse, f0;
                float  aBase;       // 底层 α（可能已被清漆修正）
                float  aCoat;       // 清漆层 α
                float  coatMask;
                float  coatFv;      // 清漆在视线方向的菲涅尔，用来衰减底层
            };
            //#endregion

            //#region shade
            half3 ShadeOneLight(MaterialCtx m, Light light)
            {
                float3 L = light.direction;
                float3 H = normalize(m.V + L);
                float NoL = saturate(dot(m.N, L));
                float NoV = max(dot(m.N, m.V), 1e-4);
                float NoH = saturate(dot(m.N, H));
                float VoH = saturate(dot(m.V, H));

                // 底层：漫反射 + 金属片法线下的 GGX
                float3 baseBRDF = m.diffuse * ADV_INV_PI + AdvSpecularGGX(m.flakeN, m.V, L, m.aBase, m.f0);

                // 清漆层：F0 = 0.04 的电介质 GGX，用宏观法线（漆面是平的）
                float  Fc = AdvF_Schlick(0.04, 1.0, VoH);
                float  coatSpec = AdvD_GGX(NoH, m.aCoat) * AdvV_SmithGGX(NoV, NoL, m.aCoat) * Fc;

                // 能量衰减：被清漆反射掉的那部分光不会再到达底层
                float attenuation = lerp(1.0, 1.0 - m.coatMask * m.coatFv, _CoatEnergy);
                float3 brdf = baseBRDF * attenuation + coatSpec * m.coatMask;

                return brdf * PI * light.color * (NoL * light.distanceAttenuation * light.shadowAttenuation);
            }
            //#endregion

            #include "Assets/Cookbook/Ch12/LightLoop.hlsl"

            //#region flake
            // 程序化金属片：把 UV 切成很小的格子，每格一个随机倾斜的法线
            float3 Hash33(float3 p)
            {
                p = frac(p * float3(0.1031, 0.1030, 0.0973));
                p += dot(p, p.yxz + 33.33);
                return frac((p.xxy + p.yxx) * p.zyx);
            }
            float3 FlakeNormal(float2 uv, float3 T, float3 B, float3 N)
            {
                float2 cell = floor(uv * _FlakeDensity);
                float3 r = Hash33(float3(cell, 7.0)) * 2.0 - 1.0;
                return normalize(N + (r.x * T + r.y * B) * _FlakeStrength);
            }
            //#endregion

            //#region frag
            half4 frag(Varyings i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                float3 T, B, N; Ch12BuildFrame(i, T, B, N);
                float3 V = GetWorldSpaceNormalizeViewDir(i.positionWS);
                float2 screenUV = GetNormalizedScreenSpaceUV(i.positionCS);
                float NoV = saturate(dot(N, V));

                MaterialCtx m;
                m.N = N; m.V = V;
                m.flakeN = FlakeNormal(i.uv, T, B, N);
                m.coatMask = _CoatMask;
                m.f0 = lerp(0.04, _BaseColor.rgb, _Metallic);
                m.diffuse = _BaseColor.rgb * (1.0 - _Metallic) * 0.96;

                float prBase = 1.0 - _Smoothness;
                float aBase = max(prBase * prBase, 0.002);
                if (_CoatAffectBase > 0.5)
                {
                    // ① 折射让底层波瓣变宽：α → 等效 Blinn-Phong 指数，乘 (1/1.5)²，再换回来（与 URP 的做法相同）
                    float ieta = lerp(1.0, 1.0 / 1.5, m.coatMask);
                    float n = 2.0 / (aBase * aBase) - 2.0;
                    aBase = sqrt(2.0 / (n * ieta * ieta + 2.0));
                    // ② 底层 F0 原本相对空气，现在相对 IOR=1.5 的漆：数值会变小、颜色更饱和
                    float3 f0Coat = saturate(m.f0 * (m.f0 * 0.526868 + 0.529324) - 0.0482256);
                    m.f0 = lerp(m.f0, f0Coat, m.coatMask);
                }
                m.aBase = aBase;
                float prCoat = 1.0 - _CoatSmoothness;
                m.aCoat = max(prCoat * prCoat, 0.002);
                m.coatFv = AdvF_Schlick(0.04, 1.0, NoV);

                half3 color = AccumulateDirectLighting(m, i.positionWS, screenUV);

                // 间接光：底层用（修正后的）底层粗糙度，清漆用自己的粗糙度各采一次反射
                float prBaseEff = sqrt(m.aBase);
                float2 AB = AdvEnvBRDFApprox(prBaseEff, saturate(dot(m.flakeN, V)));
                float3 baseIndirect = SampleSH(N) * m.diffuse
                    + GlossyEnvironmentReflection(reflect(-V, m.flakeN), i.positionWS, prBaseEff, 1.0, screenUV) * (m.f0 * AB.x + AB.y);
                float2 ABc = AdvEnvBRDFApprox(prCoat, NoV);
                float3 coatIndirect = GlossyEnvironmentReflection(reflect(-V, N), i.positionWS, prCoat, 1.0, screenUV) * (0.04 * ABc.x + ABc.y);

                float attenuation = lerp(1.0, 1.0 - m.coatMask * m.coatFv, _CoatEnergy);
                color += baseIndirect * attenuation + coatIndirect * m.coatMask;

                color = MixFog(color, i.fogFactor);
                return half4(color, 1);
            }
            //#endregion
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0 Cull Back
            HLSLPROGRAM
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment
            #pragma multi_compile_instancing
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            // URP 自带的阴影 Pass 只在 _ALPHATEST_ON 时才读 _BaseMap，其余部分与材质无关，直接复用
            #include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"
            ENDHLSL
        }
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R Cull Back
            HLSLPROGRAM
            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment
            #pragma multi_compile_instancing
            #include "Packages/com.unity.render-pipelines.universal/Shaders/DepthOnlyPass.hlsl"
            ENDHLSL
        }
        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode"="DepthNormals" }
            ZWrite On Cull Back
            HLSLPROGRAM
            #pragma vertex DepthNormalsVertex
            #pragma fragment DepthNormalsFragment
            #pragma multi_compile_instancing
            #include "Packages/com.unity.render-pipelines.universal/Shaders/DepthNormalsPass.hlsl"
            ENDHLSL
        }
    }
}
