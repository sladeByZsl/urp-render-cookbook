// 各向异性 GGX：拉丝金属。切线方向 T = 拉丝（划痕）方向。
Shader "Cookbook/Ch12/Anisotropic"
{
    Properties
    {
        [MainColor] _BaseColor ("Base Color", Color) = (0.92, 0.92, 0.9, 1)
        _Metallic ("Metallic", Range(0, 1)) = 1
        _Smoothness ("Smoothness", Range(0, 1)) = 0.6
        _Anisotropy ("Anisotropy", Range(-0.95, 0.95)) = 0.8
        [KeywordEnum(Tangent, Bitangent, Radial)] _Dir ("Brush Direction", Float) = 0
        _BrushTex ("Brush Streaks (R)", 2D) = "gray" {}
        _BrushStrength ("Brush Streak Strength", Range(0, 1)) = 0.3
        [Toggle] _AnisoIBL ("Bent Normal for IBL", Float) = 1
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
        CBUFFER_START(UnityPerMaterial)
            float4 _BrushTex_ST;
            half4 _BaseColor;
            half  _Metallic, _Smoothness, _Anisotropy, _BrushStrength, _AnisoIBL;
        CBUFFER_END
        TEXTURE2D(_BrushTex); SAMPLER(sampler_BrushTex);
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex Ch12Vert
            #pragma fragment frag
            #pragma shader_feature_local_fragment _DIR_TANGENT _DIR_BITANGENT _DIR_RADIAL
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
                float3 N, V, T, B;
                float3 diffuse, f0;
                float  at, ab;
            };

            //#region shade
            half3 ShadeOneLight(MaterialCtx m, Light light)
            {
                float3 L = light.direction;
                float3 H = normalize(m.V + L);
                float NoL = saturate(dot(m.N, L));
                float NoV = max(dot(m.N, m.V), 1e-4);
                float NoH = saturate(dot(m.N, H));
                float VoH = saturate(dot(m.V, H));

                float D = AdvD_GGXAniso(dot(m.T, H), dot(m.B, H), NoH, m.at, m.ab);
                float Vis = AdvV_SmithGGXAniso(dot(m.T, m.V), dot(m.B, m.V), NoV,
                                               dot(m.T, L), dot(m.B, L), NoL, m.at, m.ab);
                float3 F = AdvF_Schlick(m.f0, 1.0, VoH);

                float3 brdf = m.diffuse * ADV_INV_PI + D * Vis * F;
                return brdf * PI * light.color * (NoL * light.distanceAttenuation * light.shadowAttenuation);
            }
            //#endregion

            #include "Assets/Cookbook/Ch12/LightLoop.hlsl"

            half4 frag(Varyings i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                float3 T, B, N; Ch12BuildFrame(i, T, B, N);
                float3 V = GetWorldSpaceNormalizeViewDir(i.positionWS);
                float2 screenUV = GetNormalizedScreenSpaceUV(i.positionCS);

                //#region dir
                // 选择拉丝方向；条纹贴图的纹路沿 U 方向，采样坐标也跟着转
                float2 streakUV = i.uv;
            #if defined(_DIR_BITANGENT)
                float3 tmp = T; T = B; B = -tmp;
                streakUV = i.uv.yx;
            #elif defined(_DIR_RADIAL)
                // 以 UV 中心为圆心的同心圆拉丝（锅底、CD 纹）：切线 = 圆周方向
                float2 d = i.uv - 0.5;
                float2 c = normalize(float2(-d.y, d.x) + 1e-5);
                T = normalize(c.x * T + c.y * B);
                B = cross(N, T);
                streakUV = float2(0.5, length(d) * 2.0);   // 条纹只随半径变化 → 同心圆
            #endif
                //#endregion

                // 拉丝条纹：一点点调制粗糙度和颜色，让表面“有料”
                half streak = SAMPLE_TEXTURE2D(_BrushTex, sampler_BrushTex, streakUV * _BrushTex_ST.xy + _BrushTex_ST.zw).r;
                float pr = saturate(1.0 - _Smoothness + (streak - 0.5) * _BrushStrength * 0.6);
                float a = max(pr * pr, 0.002);
                half3 albedo = _BaseColor.rgb * lerp(1.0, 0.75 + 0.5 * streak, _BrushStrength);

                MaterialCtx m;
                m.N = N; m.V = V; m.T = T; m.B = B;
                m.f0 = lerp(0.04, albedo, _Metallic);
                m.diffuse = albedo * (1.0 - _Metallic) * 0.96;
                AdvAnisoRoughness(a, _Anisotropy, m.at, m.ab);

                half3 color = AccumulateDirectLighting(m, i.positionWS, screenUV);

                //#region bent
                // 各向异性的环境反射：没法预滤波，常用“弯曲法线”近似（Filament 的做法）
                // grooveDir 是光滑的方向（划痕走向）；anisoN = V 投影到垂直于它的平面上，
                // 把法线朝 anisoN 扭一扭，反射就会沿“粗糙方向”被拉长
                float3 grooveDir = _Anisotropy >= 0.0 ? T : B;
                float3 anisoT = cross(grooveDir, V);
                float3 anisoN = cross(anisoT, grooveDir);
                float bend = abs(_Anisotropy) * saturate(5.0 * pr) * _AnisoIBL;
                float3 bentN = normalize(lerp(N, anisoN, bend));
                float3 R = reflect(-V, bentN);
                //#endregion

                float2 AB = AdvEnvBRDFApprox(pr, saturate(dot(N, V)));
                color += SampleSH(N) * m.diffuse;
                color += GlossyEnvironmentReflection(R, i.positionWS, pr, 1.0, screenUV) * (m.f0 * AB.x + AB.y);

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
