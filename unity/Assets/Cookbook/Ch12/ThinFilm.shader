// 薄膜干涉（Iridescence）：肥皂泡、油膜、甲虫壳、回火金属的彩虹色。
// 菲涅尔项 F 被替换成“三层结构的干涉反射率”，其余仍是 GGX。
Shader "Cookbook/Ch12/ThinFilm"
{
    Properties
    {
        [MainColor] _BaseColor ("Base Diffuse Color", Color) = (0.02, 0.02, 0.025, 1)
        [KeywordEnum(Spectral, RGB3, Belcour)] _Film ("Film Evaluation", Float) = 0
        _BaseF0 ("Base F0 (under film)", Range(0.02, 0.95)) = 0.04
        _Thickness ("Film Thickness (nm)", Range(0, 1200)) = 400
        _ThicknessTex ("Thickness Variation (R)", 2D) = "gray" {}
        _ThicknessVar ("Thickness Variation (nm)", Range(0, 800)) = 0
        _FilmIOR ("Film IOR", Range(1.0, 2.5)) = 1.33
        _Smoothness ("Smoothness", Range(0, 1)) = 0.9
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
        CBUFFER_START(UnityPerMaterial)
            float4 _ThicknessTex_ST;
            half4 _BaseColor;
            half  _BaseF0, _Thickness, _ThicknessVar, _FilmIOR, _Smoothness;
        CBUFFER_END
        TEXTURE2D(_ThicknessTex); SAMPLER(sampler_ThicknessTex);
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex Ch12Vert
            #pragma fragment frag
            #pragma shader_feature_local_fragment _FILM_SPECTRAL _FILM_RGB3 _FILM_BELCOUR
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

            //#region film
            float3 FilmFresnel(float cosTheta, float thickness)
            {
            #if defined(_FILM_RGB3)
                // 偷懒版：只在 R/G/B 三个代表波长上算一次 Airy 反射率
                float sin2 = (1.0 - cosTheta * cosTheta) / (_FilmIOR * _FilmIOR);
                float opd = 2.0 * _FilmIOR * thickness * sqrt(saturate(1.0 - sin2));
                float r12 = -sqrt(AdvF_Schlick(Sq((1.0 - _FilmIOR) / (1.0 + _FilmIOR)), 1.0, cosTheta));
                float baseIOR = (1.0 + sqrt(_BaseF0)) / (1.0 - sqrt(min(_BaseF0, 0.99)));
                float r23 = sign(_FilmIOR - baseIOR) * sqrt(Sq((_FilmIOR - baseIOR) / (_FilmIOR + baseIOR)));
                return float3(AdvAiryReflectance(r12, r23, opd, 650.0),
                              AdvAiryReflectance(r12, r23, opd, 532.0),
                              AdvAiryReflectance(r12, r23, opd, 450.0));
            #elif defined(_FILM_BELCOUR)
                // core 包里 HDRP 用的 Belcour & Barla 2017 实现；它的厚度参数是 0~1 的归一化值
                return EvalIridescence(1.0, cosTheta, saturate(thickness / 1000.0), _BaseF0.xxx);
            #else
                return AdvThinFilm(cosTheta, thickness, _FilmIOR, _BaseF0);
            #endif
            }
            //#endregion

            struct MaterialCtx
            {
                float3 N, V;
                float3 diffuse;
                float  a, thickness;
            };

            half3 ShadeOneLight(MaterialCtx m, Light light)
            {
                float3 L = light.direction;
                float3 H = normalize(m.V + L);
                float NoL = saturate(dot(m.N, L));
                float NoV = max(dot(m.N, m.V), 1e-4);
                float NoH = saturate(dot(m.N, H));
                float VoH = saturate(dot(m.V, H));
                float3 F = FilmFresnel(VoH, m.thickness);   // 用薄膜反射率替换 Schlick
                float3 spec = AdvD_GGX(NoH, m.a) * AdvV_SmithGGX(NoV, NoL, m.a) * F;
                float3 brdf = m.diffuse * ADV_INV_PI + spec;
                return brdf * PI * light.color * (NoL * light.distanceAttenuation * light.shadowAttenuation);
            }

            #include "Assets/Cookbook/Ch12/LightLoop.hlsl"

            half4 frag(Varyings i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                float3 T, B, N; Ch12BuildFrame(i, T, B, N);
                float3 V = GetWorldSpaceNormalizeViewDir(i.positionWS);
                float2 screenUV = GetNormalizedScreenSpaceUV(i.positionCS);
                float NoV = saturate(dot(N, V));

                half tn = SAMPLE_TEXTURE2D(_ThicknessTex, sampler_ThicknessTex, TRANSFORM_TEX(i.uv, _ThicknessTex)).r;

                MaterialCtx m;
                m.N = N; m.V = V;
                m.diffuse = _BaseColor.rgb;
                m.thickness = max(_Thickness + (tn - 0.5) * 2.0 * _ThicknessVar, 0.0);
                float pr = 1.0 - _Smoothness;
                m.a = max(pr * pr, 0.002);

                half3 color = AccumulateDirectLighting(m, i.positionWS, screenUV);

                // 环境反射同样用薄膜反射率，角度取 N·V；AB.x + AB.y 近似粗糙度带来的能量损失
                float2 AB = AdvEnvBRDFApprox(pr, NoV);
                color += SampleSH(N) * m.diffuse;
                color += GlossyEnvironmentReflection(reflect(-V, N), i.positionWS, pr, 1.0, screenUV)
                       * FilmFresnel(NoV, m.thickness) * (AB.x + AB.y);

                color = MixFog(color, i.fogFactor);
                return half4(color, 1);
            }
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
