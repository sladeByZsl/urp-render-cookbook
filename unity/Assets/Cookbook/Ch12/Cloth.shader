// 布料：Charlie sheen 法线分布 + Neubelt 可见性 + 包裹漫反射与次表面色（Filament 布料模型的思路）。
Shader "Cookbook/Ch12/Cloth"
{
    Properties
    {
        [MainColor] _BaseColor ("Base Color", Color) = (0.35, 0.03, 0.08, 1)
        [KeywordEnum(GGX, Charlie, Subsurface)] _Model ("Model", Float) = 2
        _Smoothness ("Smoothness (GGX only)", Range(0, 1)) = 0.35
        _SheenColor ("Sheen Color", Color) = (0.9, 0.55, 0.6, 1)
        _SheenRoughness ("Sheen Roughness", Range(0.05, 1)) = 0.45
        _SubsurfaceColor ("Subsurface Color", Color) = (0.45, 0.05, 0.1, 1)
        _Wrap ("Diffuse Wrap", Range(0, 1)) = 0.5
        _WeaveScale ("Weave Scale", Float) = 160
        _WeaveStrength ("Weave Strength", Range(0, 1)) = 0.25
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
        CBUFFER_START(UnityPerMaterial)
            half4 _BaseColor, _SheenColor, _SubsurfaceColor;
            half  _Smoothness, _SheenRoughness, _Wrap;
            float _WeaveScale;
            half  _WeaveStrength;
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
            #pragma shader_feature_local_fragment _MODEL_GGX _MODEL_CHARLIE _MODEL_SUBSURFACE
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

            struct MaterialCtx
            {
                float3 N, V;
                float3 albedo, sheen;
                float  a;          // GGX 用的 α
                float  sheenA;     // Charlie 用的 α
            };

            //#region shade
            half3 ShadeOneLight(MaterialCtx m, Light light)
            {
                float3 L = light.direction;
                float3 H = normalize(m.V + L);
                float NoLu = dot(m.N, L);
                float NoL = saturate(NoLu);
                float NoV = max(dot(m.N, m.V), 1e-4);
                float NoH = saturate(dot(m.N, H));
                float atten = light.distanceAttenuation * light.shadowAttenuation;

            #if defined(_MODEL_GGX)
                // 对照组：把布当成普通电介质
                float3 brdf = m.albedo * ADV_INV_PI + AdvSpecularGGX(m.N, m.V, L, m.a, 0.04);
                return brdf * PI * light.color * (NoL * atten);
            #else
                // 镜面：Charlie 分布 × Neubelt 可见性 × sheen 颜色（布料没有明显的菲涅尔变化，直接用颜色当 F）
                float3 Fr = AdvD_Charlie(NoH, m.sheenA) * AdvV_Neubelt(NoV, NoL) * m.sheen;
              #if defined(_MODEL_SUBSURFACE)
                // 漫反射：包裹 + 次表面色，光“渗”进暗部并带上颜色
                float3 Fd = m.albedo * ADV_INV_PI * AdvWrapDiffuse(NoLu, _Wrap);
                Fd *= saturate(_SubsurfaceColor.rgb + NoL);
                return (Fd + Fr * NoL) * PI * light.color * atten;
              #else
                float3 Fd = m.albedo * ADV_INV_PI;
                return (Fd + Fr) * PI * light.color * (NoL * atten);
              #endif
            #endif
            }
            //#endregion

            #include "Assets/Cookbook/Ch12/LightLoop.hlsl"

            half4 frag(Varyings i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                float3 T, B, N; Ch12BuildFrame(i, T, B, N);
                float3 V = GetWorldSpaceNormalizeViewDir(i.positionWS);
                float2 screenUV = GetNormalizedScreenSpaceUV(i.positionCS);
                float NoV = saturate(dot(N, V));

                //#region weave
                // 程序化平纹：经纬线交替压在上面，用两组正弦的乘积近似线的明暗
                float2 w = i.uv * _WeaveScale;
                float warp = abs(sin(w.x * PI)) * step(0.5, frac(w.y * 0.5 + floor(w.x) * 0.5));
                float weft = abs(sin(w.y * PI)) * (1.0 - step(0.5, frac(w.y * 0.5 + floor(w.x) * 0.5)));
                float thread = saturate(warp + weft);
                half weave = lerp(1.0, lerp(0.7, 1.1, thread), _WeaveStrength);
                //#endregion

                MaterialCtx m;
                m.N = N; m.V = V;
                m.albedo = _BaseColor.rgb * weave;
                m.sheen = _SheenColor.rgb * weave;
                float pr = 1.0 - _Smoothness;
                m.a = max(pr * pr, 0.002);
                m.sheenA = max(_SheenRoughness * _SheenRoughness, 0.01);

                half3 color = AccumulateDirectLighting(m, i.positionWS, screenUV);

                // 间接光
                color += SampleSH(N) * m.albedo;
            #if defined(_MODEL_GGX)
                float2 AB = AdvEnvBRDFApprox(pr, NoV);
                color += GlossyEnvironmentReflection(reflect(-V, N), i.positionWS, pr, 1.0, screenUV) * (0.04 * AB.x + AB.y);
            #else
                // 环境 sheen：严格做法是像 split-sum 那样把 D_Charlie·V_Neubelt 预积分成 LUT；
                // 这里用一个随掠射角增强的经验系数代替，够用且便宜
                float sheenEnv = lerp(0.12, 0.35, _SheenRoughness) * (0.4 + 0.6 * pow(1.0 - NoV, 2.0));
                color += GlossyEnvironmentReflection(reflect(-V, N), i.positionWS, _SheenRoughness, 1.0, screenUV) * m.sheen * sheenEnv;
            #endif

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
