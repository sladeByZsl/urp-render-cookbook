// 皮肤：三种次表面散射近似的漫反射 + 双瓣 GGX 高光。
//   LAMBERT —— 对照组；WRAP —— 按通道不同包裹量的 Wrap Lighting；LUT —— 预积分皮肤散射（Penner 2011）
Shader "Cookbook/Ch12/Skin"
{
    Properties
    {
        [MainColor] _BaseColor ("Skin Albedo", Color) = (0.85, 0.6, 0.5, 1)
        [KeywordEnum(Lambert, Wrap, LUT)] _Diffuse ("Diffuse Model", Float) = 2
        _ScatterColor ("Wrap Scatter Color", Color) = (0.6, 0.2, 0.1, 1)
        _Wrap ("Wrap Amount", Range(0, 1)) = 0.5
        [NoScaleOffset] _SkinLUT ("Pre-integrated LUT", 2D) = "white" {}
        _CurvatureScale ("Curvature Scale (1/m -> LUT v)", Range(0, 1)) = 0.1
        _Curvature ("Curvature Override (<0 = auto)", Range(-1, 1)) = -1
        _Smoothness ("Smoothness", Range(0, 1)) = 0.6
        _SpecularF0 ("Specular F0", Range(0, 0.08)) = 0.028
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
        CBUFFER_START(UnityPerMaterial)
            half4 _BaseColor, _ScatterColor;
            half  _Wrap, _CurvatureScale, _Curvature, _Smoothness, _SpecularF0;
        CBUFFER_END
        TEXTURE2D(_SkinLUT); SAMPLER(sampler_SkinLUT);
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex Ch12Vert
            #pragma fragment frag
            #pragma shader_feature_local_fragment _DIFFUSE_LAMBERT _DIFFUSE_WRAP _DIFFUSE_LUT
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
                float3 albedo;
                float  curvature;   // 0~1，查 LUT 的 v 坐标
                float  a;
            };

            //#region diffuse
            float3 SkinDiffuse(MaterialCtx m, float NoLu, float shadow)
            {
            #if defined(_DIFFUSE_WRAP)
                // 每个通道包裹量不同：红光在皮下走得最远，所以红通道包得最多
                // 阴影同样折进 N·L：阴影里的点按“刚好背光”处理，包裹项让阴影边缘也透出一点红
                float3 w = _Wrap * _ScatterColor.rgb;
                float ndl = lerp(min(NoLu, 0.0), NoLu, shadow);
                return saturate((ndl + w) / (1.0 + w));
            #elif defined(_DIFFUSE_LUT)
                // 预积分 LUT：u = N·L 映射到 0~1，v = 曲率
                // 阴影先折进 N·L 再查表，让阴影边缘也带上散射的红色过渡
                float u = lerp(min(NoLu, 0.0), NoLu, shadow) * 0.5 + 0.5;
                return SAMPLE_TEXTURE2D_LOD(_SkinLUT, sampler_SkinLUT, float2(u, m.curvature), 0).rgb;
            #else
                return saturate(NoLu) * shadow;
            #endif
            }
            //#endregion

            //#region shade
            half3 ShadeOneLight(MaterialCtx m, Light light)
            {
                float3 L = light.direction;
                float NoLu = dot(m.N, L);
                float NoL = saturate(NoLu);
                float3 diffuse = m.albedo * SkinDiffuse(m, NoLu, light.shadowAttenuation);

                // 双瓣高光：一个偏光滑、一个偏粗糙，各占一半，模拟皮脂层 + 角质层
                float3 spec = 0.5 * AdvSpecularGGX(m.N, m.V, L, m.a, _SpecularF0)
                            + 0.5 * AdvSpecularGGX(m.N, m.V, L, saturate(m.a * 2.2), _SpecularF0);
                spec *= PI * NoL * light.shadowAttenuation;

                return (diffuse + spec) * light.color * light.distanceAttenuation;
            }
            //#endregion

            #include "Assets/Cookbook/Ch12/LightLoop.hlsl"

            half4 frag(Varyings i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                float3 T, B, N; Ch12BuildFrame(i, T, B, N);
                float3 V = GetWorldSpaceNormalizeViewDir(i.positionWS);
                float2 screenUV = GetNormalizedScreenSpaceUV(i.positionCS);

                //#region curvature
                // 曲率 = 法线变化量 / 位置变化量，用屏幕空间导数估计（单位 1/米）
                float curv = length(fwidth(N)) / max(length(fwidth(i.positionWS)), 1e-5);
                curv = saturate(curv * _CurvatureScale);   // 换算到 LUT 的 0~1，比例取决于场景单位和 LUT 的定义
                if (_Curvature >= 0) curv = _Curvature;
                //#endregion

                MaterialCtx m;
                m.N = N; m.V = V;
                m.albedo = _BaseColor.rgb;
                m.curvature = curv;
                float pr = 1.0 - _Smoothness;
                m.a = max(pr * pr, 0.002);

                half3 color = AccumulateDirectLighting(m, i.positionWS, screenUV);

                float NoV = saturate(dot(N, V));
                float2 AB = AdvEnvBRDFApprox(pr, NoV);
                color += SampleSH(N) * m.albedo;
                color += GlossyEnvironmentReflection(reflect(-V, N), i.positionWS, pr, 1.0, screenUV) * (_SpecularF0 * AB.x + AB.y);

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
