// 一个“全局光照就绪”的自写 Shader：球谐 / 光照贴图 / 动态光照贴图 / Shadowmask / 反射探针（含混合与盒体投影）/
// SSAO / 材质 AO / 自发光，并提供 Meta Pass 参与烘焙。直接光沿用 URP 的 BRDF，便于与 URP Lit 对照。
Shader "Cookbook/Ch08/GILit"
{
    Properties
    {
        [MainTexture] _BaseMap("Albedo", 2D) = "white" {}
        [MainColor] _BaseColor("Color", Color) = (1, 1, 1, 1)
        _Metallic("Metallic", Range(0, 1)) = 0
        _Smoothness("Smoothness", Range(0, 1)) = 0.5
        [Toggle(_NORMALMAP)] _UseNormalMap("Use Normal Map", Float) = 0
        [NoScaleOffset][Normal] _BumpMap("Normal Map", 2D) = "bump" {}
        _BumpScale("Normal Scale", Float) = 1
        [Toggle(_OCCLUSIONMAP)] _UseOcclusionMap("Use Occlusion Map", Float) = 0
        [NoScaleOffset] _OcclusionMap("Occlusion (G)", 2D) = "white" {}
        _OcclusionStrength("Occlusion Strength", Range(0, 1)) = 1
        [Toggle(_EMISSION)] _UseEmission("Emission", Float) = 0
        [HDR] _EmissionColor("Emission Color", Color) = (0, 0, 0, 1)
        [NoScaleOffset] _EmissionMap("Emission Map", 2D) = "white" {}
        [ToggleOff(_ENVIRONMENTREFLECTIONS_OFF)] _EnvironmentReflections("Environment Reflections", Float) = 1
        [Enum(Full,0,IndirectDiffuse,1,IndirectSpecular,2,Direct,3,AOOnDirectToo,4)] _DebugView("Debug View", Float) = 0
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half4 _BaseColor;
            half4 _EmissionColor;
            half _Metallic;
            half _Smoothness;
            half _BumpScale;
            half _OcclusionStrength;
            half _DebugView;
        CBUFFER_END
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            HLSLPROGRAM
            #pragma target 2.0
            #pragma vertex vert
            #pragma fragment frag

            //#region keywords
            // 材质开关
            #pragma shader_feature_local _NORMALMAP
            #pragma shader_feature_local_fragment _OCCLUSIONMAP
            #pragma shader_feature_local_fragment _EMISSION
            #pragma shader_feature_local_fragment _ENVIRONMENTREFLECTIONS_OFF
            // URP 管线关键字（与 URP 14 Lit.shader 一致的子集）
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ EVALUATE_SH_MIXED EVALUATE_SH_VERTEX
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BLENDING
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BOX_PROJECTION
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #pragma multi_compile_fragment _ _SCREEN_SPACE_OCCLUSION
            #pragma multi_compile _ _FORWARD_PLUS
            // Unity 引擎根据烘焙结果自动打开的关键字
            #pragma multi_compile _ LIGHTMAP_SHADOW_MIXING
            #pragma multi_compile _ SHADOWS_SHADOWMASK
            #pragma multi_compile _ DIRLIGHTMAP_COMBINED
            #pragma multi_compile _ LIGHTMAP_ON
            #pragma multi_compile _ DYNAMICLIGHTMAP_ON
            #pragma multi_compile_fog
            //#endregion

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_BaseMap);      SAMPLER(sampler_BaseMap);
            TEXTURE2D(_BumpMap);      SAMPLER(sampler_BumpMap);
            TEXTURE2D(_OcclusionMap); SAMPLER(sampler_OcclusionMap);
            TEXTURE2D(_EmissionMap);  SAMPLER(sampler_EmissionMap);

            //#region structs
            struct Attributes
            {
                float4 positionOS        : POSITION;
                float3 normalOS          : NORMAL;
                float4 tangentOS         : TANGENT;
                float2 uv                : TEXCOORD0;
                float2 staticLightmapUV  : TEXCOORD1;   // 光照贴图 UV（导入设置 Generate Lightmap UVs 生成的 UV2）
                float2 dynamicLightmapUV : TEXCOORD2;   // Enlighten 实时 GI 用的 UV3
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                half3  normalWS   : TEXCOORD2;
            #if defined(_NORMALMAP)
                half4  tangentWS  : TEXCOORD3;
            #endif
                // 有光照贴图时声明 float2 staticLightmapUV，否则声明 half3 vertexSH（逐顶点 SH 结果）
                DECLARE_LIGHTMAP_OR_SH(staticLightmapUV, vertexSH, 4);
            #ifdef DYNAMICLIGHTMAP_ON
                float2 dynamicLightmapUV : TEXCOORD5;
            #endif
                half fogFactor : TEXCOORD6;
            };
            //#endregion

            //#region vert
            Varyings vert(Attributes input)
            {
                Varyings o = (Varyings)0;
                VertexPositionInputs pos = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs nrm = GetVertexNormalInputs(input.normalOS, input.tangentOS);
                o.positionCS = pos.positionCS;
                o.positionWS = pos.positionWS;
                o.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                o.normalWS = nrm.normalWS;
            #if defined(_NORMALMAP)
                o.tangentWS = half4(nrm.tangentWS, input.tangentOS.w * GetOddNegativeScale());
            #endif
                // 光照贴图 UV：乘上 unity_LightmapST（每个物体在图集里的缩放与偏移）
                OUTPUT_LIGHTMAP_UV(input.staticLightmapUV, unity_LightmapST, o.staticLightmapUV);
            #ifdef DYNAMICLIGHTMAP_ON
                o.dynamicLightmapUV = input.dynamicLightmapUV * unity_DynamicLightmapST.xy + unity_DynamicLightmapST.zw;
            #endif
                // 没有光照贴图时：EVALUATE_SH_VERTEX 在这里算完整 SH，EVALUATE_SH_MIXED 只算 L2，逐像素模式什么都不算
                OUTPUT_SH(o.normalWS, o.vertexSH);
                o.fogFactor = ComputeFogFactor(pos.positionCS.z);
                return o;
            }
            //#endregion

            //#region frag
            half4 frag(Varyings i) : SV_Target
            {
                // ---------- 表面属性 ----------
                half4 baseSample = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv) * _BaseColor;
                half3 albedo = baseSample.rgb;
                half alpha = 1;
            #if defined(_OCCLUSIONMAP)
                half occlusion = LerpWhiteTo(SAMPLE_TEXTURE2D(_OcclusionMap, sampler_OcclusionMap, i.uv).g, _OcclusionStrength);
            #else
                half occlusion = 1;
            #endif
            #if defined(_EMISSION)
                half3 emission = SAMPLE_TEXTURE2D(_EmissionMap, sampler_EmissionMap, i.uv).rgb * _EmissionColor.rgb;
            #else
                half3 emission = 0;
            #endif

            #if defined(_NORMALMAP)
                half3 normalTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, i.uv), _BumpScale);
                float3 bitangent = i.tangentWS.w * cross(i.normalWS, i.tangentWS.xyz);
                half3 normalWS = TransformTangentToWorld(normalTS, half3x3(i.tangentWS.xyz, bitangent, i.normalWS));
            #else
                half3 normalWS = i.normalWS;
            #endif
                normalWS = NormalizeNormalPerPixel(normalWS);
                half3 viewDirWS = GetWorldSpaceNormalizeViewDir(i.positionWS);
                float2 screenUV = GetNormalizedScreenSpaceUV(i.positionCS);

                BRDFData brdf;
                InitializeBRDFData(albedo, _Metallic, half3(0, 0, 0), _Smoothness, alpha, brdf);

                // ---------- ① 间接漫反射：光照贴图 或 球谐 ----------
            #if defined(DYNAMICLIGHTMAP_ON)
                half3 bakedGI = SAMPLE_GI(i.staticLightmapUV, i.dynamicLightmapUV, i.vertexSH, normalWS);
            #else
                half3 bakedGI = SAMPLE_GI(i.staticLightmapUV, i.vertexSH, normalWS);
            #endif

                // ---------- ② 主光 + 阴影（含 Shadowmask / 光照探针遮挡） ----------
                half4 shadowMask = SAMPLE_SHADOWMASK(i.staticLightmapUV);
                float4 shadowCoord = TransformWorldToShadowCoord(i.positionWS);
                Light mainLight = GetMainLight(shadowCoord, i.positionWS, shadowMask);

                // ---------- ③ AO：材质 AO 与 SSAO 取较小值，只压间接光；SSAO 还按 Direct Lighting Strength 压一点直接光 ----------
                AmbientOcclusionFactor aoFactor = CreateAmbientOcclusionFactor(screenUV, occlusion);
            #if defined(_SCREEN_SPACE_OCCLUSION)
                mainLight.color *= aoFactor.directAmbientOcclusion;
            #endif

                // Subtractive 模式下，从光照贴图里“减掉”实时阴影覆盖区域的主光贡献
                MixRealtimeAndBakedGI(mainLight, normalWS, bakedGI);

                // ---------- ④ 间接高光：反射探针（Forward+ 下走探针图集与聚类） ----------
                half3 reflectVector = reflect(-viewDirWS, normalWS);
                half3 indirectSpecular = GlossyEnvironmentReflection(reflectVector, i.positionWS,
                                                                     brdf.perceptualRoughness, half(1.0), screenUV);

                // ---------- ⑤ 组合：与 URP 的 GlobalIllumination() 相同 ----------
                half NoV = saturate(dot(normalWS, viewDirWS));
                half fresnelTerm = Pow4(1.0 - NoV);
                half3 giDiffuse  = bakedGI * brdf.diffuse;
                half3 giSpecular = indirectSpecular * EnvironmentBRDFSpecular(brdf, fresnelTerm);
                half3 gi = (giDiffuse + giSpecular) * aoFactor.indirectAmbientOcclusion;

                half3 direct = LightingPhysicallyBased(brdf, mainLight, normalWS, viewDirWS);

                half3 color = gi + direct + emission;
                // 调试视图：分别看各个分量（书中配图用）
                if (_DebugView > 0.5 && _DebugView < 1.5) color = giDiffuse * aoFactor.indirectAmbientOcclusion;
                else if (_DebugView > 1.5 && _DebugView < 2.5) color = giSpecular * aoFactor.indirectAmbientOcclusion;
                else if (_DebugView > 2.5 && _DebugView < 3.5) color = direct;
                else if (_DebugView > 3.5) color = gi + direct * occlusion + emission;   // 反例：AO 也乘到直接光上

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
            ZWrite On ZTest LEqual ColorMask 0
            HLSLPROGRAM
            #pragma vertex Ch08ShadowVert
            #pragma fragment Ch08NullFrag
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Assets/Cookbook/Ch08/Ch08Passes.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            HLSLPROGRAM
            #pragma vertex Ch08DepthVert
            #pragma fragment Ch08NullFrag
            #include "Assets/Cookbook/Ch08/Ch08Passes.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode"="DepthNormals" }
            ZWrite On
            HLSLPROGRAM
            #pragma vertex Ch08DepthNormalsVert
            #pragma fragment Ch08DepthNormalsFrag
            #include "Assets/Cookbook/Ch08/Ch08Passes.hlsl"
            ENDHLSL
        }

        // Deferred 渲染路径下，只有 UniversalForwardOnly 的材质由这个 Pass 提供法线（与 URP Unlit 的做法相同）
        Pass
        {
            Name "DepthNormalsOnly"
            Tags { "LightMode"="DepthNormalsOnly" }
            ZWrite On
            HLSLPROGRAM
            #pragma vertex Ch08DepthNormalsVert
            #pragma fragment Ch08DepthNormalsFrag
            #include "Assets/Cookbook/Ch08/Ch08Passes.hlsl"
            ENDHLSL
        }

        //#region meta
        // Meta Pass：只在烘焙光照贴图时由 Unity 调用，把物体“摊平”到光照贴图 UV 空间，
        // 输出 Albedo（决定反弹光的颜色）和 Emission（自发光作为光源参与烘焙）。
        Pass
        {
            Name "Meta"
            Tags { "LightMode"="Meta" }
            Cull Off
            HLSLPROGRAM
            #pragma vertex MetaVert
            #pragma fragment MetaFrag
            #pragma shader_feature_local_fragment _EMISSION
            #pragma shader_feature EDITOR_VISUALIZATION
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/MetaInput.hlsl"

            TEXTURE2D(_BaseMap);     SAMPLER(sampler_BaseMap);
            TEXTURE2D(_EmissionMap); SAMPLER(sampler_EmissionMap);

            struct MetaAttributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv0        : TEXCOORD0;
                float2 uv1        : TEXCOORD1;
                float2 uv2        : TEXCOORD2;
            };

            struct MetaVaryings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
            #ifdef EDITOR_VISUALIZATION
                float2 VizUV      : TEXCOORD1;
                float4 LightCoord : TEXCOORD2;
            #endif
            };

            MetaVaryings MetaVert(MetaAttributes input)
            {
                MetaVaryings o = (MetaVaryings)0;
                // unity_MetaVertexControl.x/y 决定用 uv1（静态光照贴图）还是 uv2（动态光照贴图）当作光栅化位置
                o.positionCS = UnityMetaVertexPosition(input.positionOS.xyz, input.uv1, input.uv2);
                o.uv = TRANSFORM_TEX(input.uv0, _BaseMap);
            #ifdef EDITOR_VISUALIZATION
                UnityEditorVizData(input.positionOS.xyz, input.uv0, input.uv1, input.uv2, o.VizUV, o.LightCoord);
            #endif
                return o;
            }

            half4 MetaFrag(MetaVaryings i) : SV_Target
            {
                half3 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv).rgb * _BaseColor.rgb;
                half alpha = 1;
                BRDFData brdf;
                InitializeBRDFData(albedo, _Metallic, half3(0, 0, 0), _Smoothness, alpha, brdf);

                MetaInput meta = (MetaInput)0;
                // 与 URP Lit 相同：漫反射色 + 粗糙金属的一部分高光色，近似“这块表面把光反弹成什么颜色”
                meta.Albedo = brdf.diffuse + brdf.specular * brdf.roughness * 0.5;
            #if defined(_EMISSION)
                meta.Emission = SAMPLE_TEXTURE2D(_EmissionMap, sampler_EmissionMap, i.uv).rgb * _EmissionColor.rgb;
            #endif
            #ifdef EDITOR_VISUALIZATION
                meta.VizUV = i.VizUV;
                meta.LightCoord = i.LightCoord;
            #endif
                // unity_MetaFragmentControl.x 要 Albedo，.y 要 Emission，由烘焙器分两次调用
                return UnityMetaFragment(meta);
            }
            ENDHLSL
        }
        //#endregion
    }
}
