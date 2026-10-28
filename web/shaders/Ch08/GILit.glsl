// 一个“全局光照就绪”的自写 Shader：球谐 / 光照贴图 / 动态光照贴图 / Shadowmask / 反射探针（含混合与盒体投影）/
// SSAO / 材质 AO / 自发光，并提供 Meta Pass 参与烘焙。直接光沿用 URP 的 BRDF，便于与 URP Lit 对照。
// （GLSL 版，对应 Ch08/GILit.shader）
// 网页版没有光照烘焙：光照贴图、动态光照贴图、Shadowmask、Subtractive 混合这几条分支在浏览器里永远不会打开，
// 所以下面只保留“无光照贴图”的路径（SAMPLE_GI 退化为逐像素 SampleSH），Meta Pass 也不移植。
Shader "Cookbook/Ch08/GILit"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform vec4  _BaseMap_ST;
        uniform vec4  _BaseColor;
        uniform vec4  _EmissionColor;
        uniform float _Metallic;
        uniform float _Smoothness;
        uniform float _BumpScale;
        uniform float _OcclusionStrength;
        uniform float _DebugView;
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            GLSLPROGRAM
            //#region keywords
            // 材质开关
            #pragma shader_feature_local _NORMALMAP
            #pragma shader_feature_local_fragment _OCCLUSIONMAP
            #pragma shader_feature_local_fragment _EMISSION
            #pragma shader_feature_local_fragment _ENVIRONMENTREFLECTIONS_OFF
            // URP 管线关键字（主光阴影、软阴影、SSAO、雾）在网页版由引擎统一处理，不用声明；
            // LIGHTMAP_ON / DYNAMICLIGHTMAP_ON / SHADOWS_SHADOWMASK 等烘焙关键字网页版没有
            //#endregion

            uniform sampler2D _BaseMap;
            uniform sampler2D _BumpMap;
            uniform sampler2D _OcclusionMap;
            uniform sampler2D _EmissionMap;

            //#region structs
            VARYING vec2 uv;
            VARYING vec3 positionWS;
            VARYING vec3 normalWS;
            VARYING vec4 tangentWS;    // 只在 _NORMALMAP 时有意义
            // HLSL 版：有光照贴图时声明 staticLightmapUV，否则声明 vertexSH（逐顶点 SH）。网页版走逐像素 SH，两者都不需要
            VARYING float fogFactor;
            //#endregion

            #ifdef VERTEX
            //#region vert
            void main()
            {
                VertexPositionInputs pos = GetVertexPositionInputs(positionOS.xyz);
                VertexNormalInputs nrm = GetVertexNormalInputs(normalOS, tangentOS);
                gl_Position = pos.positionCS;
                positionWS = pos.positionWS;
                uv = TransformTex(texcoord0.xy, _BaseMap_ST);
                normalWS = nrm.normalWS;
                tangentWS = vec4(nrm.tangentWS, tangentOS.w * GetOddNegativeScale());
                fogFactor = ComputeFogFactor(pos.positionCS.z);
            }
            //#endregion
            #endif

            #ifdef FRAGMENT
            //#region frag
            void main()
            {
                // ---------- 表面属性 ----------
                vec4 baseSample = texture(_BaseMap, uv) * _BaseColor;
                vec3 albedo = baseSample.rgb;
                float alpha = 1.0;
            #if defined(_OCCLUSIONMAP)
                float occlusion = LerpWhiteTo(texture(_OcclusionMap, uv).g, _OcclusionStrength);
            #else
                float occlusion = 1.0;
            #endif
            #if defined(_EMISSION)
                vec3 emission = texture(_EmissionMap, uv).rgb * _EmissionColor.rgb;
            #else
                vec3 emission = vec3(0.0);
            #endif

            #if defined(_NORMALMAP)
                vec3 normalTS = UnpackNormalScale(texture(_BumpMap, uv), _BumpScale);
                vec3 bitangent = tangentWS.w * cross(normalWS, tangentWS.xyz);
                vec3 N = TransformTangentToWorld(normalTS, mat3(tangentWS.xyz, bitangent, normalWS));
            #else
                vec3 N = normalWS;
            #endif
                N = NormalizeNormalPerPixel(N);
                vec3 viewDirWS = GetWorldSpaceNormalizeViewDir(positionWS);
                vec2 screenUV = GetNormalizedScreenSpaceUV(gl_FragCoord);

                BRDFData brdf;
                InitializeBRDFData(albedo, _Metallic, vec3(0.0), _Smoothness, alpha, brdf);

                // ---------- ① 间接漫反射：光照贴图 或 球谐 ----------
                // 网页版没有光照贴图，SAMPLE_GI 就是逐像素 SampleSH
                vec3 bakedGI = SampleSH(N);

                // ---------- ② 主光 + 阴影（含 Shadowmask / 光照探针遮挡） ----------
                vec4 shadowMask = vec4(1.0);     // SAMPLE_SHADOWMASK：没有 Shadowmask 时是 1
                vec4 shadowCoord = TransformWorldToShadowCoord(positionWS);
                Light mainLight = GetMainLight(shadowCoord, positionWS, shadowMask);

                // ---------- ③ AO：材质 AO 与 SSAO 取较小值，只压间接光；SSAO 还按 Direct Lighting Strength 压一点直接光 ----------
                AmbientOcclusionFactor aoFactor = GetScreenSpaceAmbientOcclusion(screenUV);
                aoFactor.indirectAmbientOcclusion = min(aoFactor.indirectAmbientOcclusion, occlusion);
                // 没开 SSAO 时 directAmbientOcclusion 恒为 1（HLSL 版用 _SCREEN_SPACE_OCCLUSION 关键字包住这一行）
                mainLight.color *= aoFactor.directAmbientOcclusion;

                // MixRealtimeAndBakedGI：Subtractive 模式下从光照贴图里“减掉”实时阴影区域的主光——没有光照贴图时什么都不做

                // ---------- ④ 间接高光：反射探针（网页版只有全局环境反射 unity_SpecCube0） ----------
                vec3 reflectVector = reflect(-viewDirWS, N);
                vec3 indirectSpecular = GlossyEnvironmentReflection(reflectVector, positionWS, brdf.perceptualRoughness, 1.0);

                // ---------- ⑤ 组合：与 URP 的 GlobalIllumination() 相同 ----------
                float NoV = saturate(dot(N, viewDirWS));
                float fresnelTerm = Pow4(1.0 - NoV);
                vec3 giDiffuse  = bakedGI * brdf.diffuse;
                vec3 giSpecular = indirectSpecular * EnvironmentBRDFSpecular(brdf, fresnelTerm);
                vec3 gi = (giDiffuse + giSpecular) * aoFactor.indirectAmbientOcclusion;

                vec3 direct = LightingPhysicallyBased(brdf, mainLight, N, viewDirWS);

                vec3 color = gi + direct + emission;
                // 调试视图：分别看各个分量（书中配图用）
                if (_DebugView > 0.5 && _DebugView < 1.5) color = giDiffuse * aoFactor.indirectAmbientOcclusion;
                else if (_DebugView > 1.5 && _DebugView < 2.5) color = giSpecular * aoFactor.indirectAmbientOcclusion;
                else if (_DebugView > 2.5 && _DebugView < 3.5) color = direct;
                else if (_DebugView > 3.5) color = gi + direct * occlusion + emission;   // 反例：AO 也乘到直接光上

                color = MixFog(color, fogFactor);
                fragColor = vec4(color, 1.0);
            }
            //#endregion
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0
            GLSLPROGRAM
            #include "Ch08/Ch08Passes.glsl"
            #ifdef VERTEX
            void main() { gl_Position = Ch08ShadowVert(); }
            #endif
            #ifdef FRAGMENT
            void main() { fragColor = Ch08NullFrag(); }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            GLSLPROGRAM
            #include "Ch08/Ch08Passes.glsl"
            #ifdef VERTEX
            void main() { gl_Position = Ch08DepthVert(); }
            #endif
            #ifdef FRAGMENT
            void main() { fragColor = Ch08NullFrag(); }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode"="DepthNormals" }
            ZWrite On
            GLSLPROGRAM
            #define CH08_DEPTH_NORMALS
            #include "Ch08/Ch08Passes.glsl"
            #ifdef VERTEX
            void main() { gl_Position = Ch08DepthNormalsVert(); }
            #endif
            #ifdef FRAGMENT
            void main() { fragColor = Ch08DepthNormalsFrag(); }
            #endif
            ENDGLSL
        }

        // DepthNormalsOnly（Deferred 专用）与 Meta（烘焙光照贴图专用）两个 Pass 网页版用不到，没有移植
    }
}
