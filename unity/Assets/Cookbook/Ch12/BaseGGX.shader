// 第 12 章的“基准材质”：自己实现的 GGX 金属度工作流。
// 后面所有进阶材质都在它的基础上增加一层或替换某一项，所以先拿它和 URP Lit 对一下数。
Shader "Cookbook/Ch12/BaseGGX"
{
    Properties
    {
        [MainTexture] _BaseMap ("Base Map", 2D) = "white" {}
        [MainColor] _BaseColor ("Base Color", Color) = (0.8, 0.8, 0.8, 1)
        _Metallic ("Metallic", Range(0, 1)) = 0
        _Smoothness ("Smoothness", Range(0, 1)) = 0.5
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        // URP 的 Shadows.hlsl 用到 CommonMaterial.hlsl 里的 LerpWhiteTo；Lit 是经由 LitInput.hlsl 间接包含的，
        // 我们复用 URP 的 ShadowCaster/DepthNormals Pass 时要自己补上
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half4  _BaseColor;
            half   _Metallic;
            half   _Smoothness;
        CBUFFER_END
        TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex Ch12Vert
            #pragma fragment frag
            //#region keywords
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
            //#endregion

            #include "Assets/Cookbook/Ch12/Ch12Common.hlsl"

            //#region shade
            struct MaterialCtx
            {
                float3 N, V;
                float3 diffuse;   // 漫反射颜色（已扣掉金属部分）
                float3 f0;        // 法向入射反射率
                float  a;         // α = 感知粗糙度²
            };

            // URP 的灯光约定：color 已经是“除过 π 的辐照度”，所以 BRDF 要整体乘 π
            half3 ShadeOneLight(MaterialCtx m, Light light)
            {
                float NoL = saturate(dot(m.N, light.direction));
                float3 brdf = m.diffuse * ADV_INV_PI + AdvSpecularGGX(m.N, m.V, light.direction, m.a, m.f0);
                return brdf * PI * light.color * (NoL * light.distanceAttenuation * light.shadowAttenuation);
            }
            //#endregion

            #include "Assets/Cookbook/Ch12/LightLoop.hlsl"

            //#region frag
            half4 frag(Varyings i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                float3 T, B, N; Ch12BuildFrame(i, T, B, N);
                float3 V = GetWorldSpaceNormalizeViewDir(i.positionWS);
                float2 screenUV = GetNormalizedScreenSpaceUV(i.positionCS);

                half4 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, TRANSFORM_TEX(i.uv, _BaseMap)) * _BaseColor;
                float perceptualRoughness = 1.0 - _Smoothness;

                MaterialCtx m;
                m.N = N; m.V = V;
                m.f0 = lerp(0.04, albedo.rgb, _Metallic);
                m.diffuse = albedo.rgb * (1.0 - _Metallic) * 0.96;
                m.a = max(perceptualRoughness * perceptualRoughness, 0.002);

                half3 color = AccumulateDirectLighting(m, i.positionWS, screenUV);

                // 间接光：漫反射用球谐，镜面用反射探针 + 环境 BRDF 近似
                float NoV = saturate(dot(N, V));
                float3 R = reflect(-V, N);
                float2 AB = AdvEnvBRDFApprox(perceptualRoughness, NoV);
                color += SampleSH(N) * m.diffuse;
                color += GlossyEnvironmentReflection(R, i.positionWS, perceptualRoughness, 1.0, screenUV) * (m.f0 * AB.x + AB.y);

                color = MixFog(color, i.fogFactor);
                return half4(color, 1);
            }
            //#endregion
            ENDHLSL
        }

        //#region passes
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
        //#endregion
    }
}
