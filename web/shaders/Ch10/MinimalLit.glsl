// 第 10 章：最小 Lit。（GLSL 版，对应 Ch10/MinimalLit.shader）
// 自己准备 SurfaceData 和 InputData，然后直接调用 URP 的 UniversalFragmentPBR —— 光照结果与 URP Lit 一致，
// 但代码量只有 Lit 的一小部分，便于看清“喂给 PBR 的到底是什么”。
// 省略了：光照贴图、视差、细节贴图、Mask Map、透明、清漆、Decal、Light Cookie、Rendering Layers、Debug Display。
Shader "Cookbook/Ch10/MinimalLit"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "UniversalMaterialType"="Lit" "Queue"="Geometry" }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            GLSLPROGRAM
            //#region keywords
            // 材质关键字：有法线贴图才开（脚本创建材质时要自己 EnableKeyword）
            #pragma shader_feature_local _NORMALMAP
            // 管线关键字（主光阴影、附加光、软阴影、SSAO、雾）：网页版引擎始终提供，不用声明；
            // 反射探针混合/盒体投影、Forward+、GPU Instancing 网页版没有
            //#endregion

            #include "Ch10/MinimalLitInput.glsl"

            VARYING vec2 uv;
            VARYING vec3 positionWS;
            VARYING vec3 normalWS;
            VARYING vec4 tangentWS;   // w = 副切线符号
            VARYING float fogFactor;

            #ifdef VERTEX
            void main()
            {
                VertexPositionInputs pos = GetVertexPositionInputs(positionOS.xyz);
                VertexNormalInputs   nrm = GetVertexNormalInputs(normalOS, tangentOS);
                gl_Position = pos.positionCS;
                positionWS  = pos.positionWS;
                normalWS    = nrm.normalWS;
                tangentWS   = vec4(nrm.tangentWS, tangentOS.w * GetOddNegativeScale());
                uv          = TransformTex(texcoord0.xy, _BaseMap_ST);
                fogFactor   = ComputeFogFactor(pos.positionCS.z);
            }
            #endif

            #ifdef FRAGMENT
            //#region surface
            SurfaceData BuildSurfaceData(vec2 uv)
            {
                SurfaceData s = InitSurfaceData();
                vec4 albedoAlpha = SampleAlbedoAlpha(uv);
                s.albedo     = albedoAlpha.rgb * _BaseColor.rgb;
                s.alpha      = 1.0;                      // 不透明
                s.metallic   = _Metallic;                // 金属度工作流：specular 留 0
                s.specular   = vec3(0.0);
                s.smoothness = _Smoothness;
                s.normalTS   = SampleNormal(uv, _BumpScale);
                s.occlusion  = 1.0;
                s.emission   = _EmissionColor.rgb;
                s.clearCoatMask = 0.0;
                s.clearCoatSmoothness = 0.0;
                return s;
            }
            //#endregion

            //#region inputdata
            InputData BuildInputData(vec3 normalTS)
            {
                InputData d = InitInputData();
                d.positionWS = positionWS;
                d.positionCS = gl_FragCoord;

            #if defined(_NORMALMAP)
                vec3 bitangent = tangentWS.w * cross(normalWS, tangentWS.xyz);
                d.tangentToWorld = mat3(tangentWS.xyz, bitangent, normalWS);   // GLSL 的 mat3 按列构造：列 = T、B、N
                d.normalWS = TransformTangentToWorld(normalTS, d.tangentToWorld);
            #else
                d.normalWS = normalWS;
            #endif
                d.normalWS = NormalizeNormalPerPixel(d.normalWS);
                d.viewDirectionWS = GetWorldSpaceNormalizeViewDir(positionWS);

                d.shadowCoord = TransformWorldToShadowCoord(positionWS);   // 逐像素算级联，省一个插值器
                d.fogCoord = fogFactor;
                d.vertexLighting = vec3(0.0);
                d.bakedGI = SampleSH(d.normalWS);                          // 无光照贴图：逐像素 SH
                d.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(gl_FragCoord);
                d.shadowMask = vec4(1.0);
                return d;
            }
            //#endregion

            //#region frag
            void main()
            {
                SurfaceData surfaceData = BuildSurfaceData(uv);
                InputData inputData = BuildInputData(surfaceData.normalTS);

                vec4 color = UniversalFragmentPBR(inputData, surfaceData);
                color.rgb = MixFog(color.rgb, inputData.fogCoord);
                fragColor = color;
            }
            //#endregion
            #endif
            ENDGLSL
        }

        //#region shadowpass
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0

            GLSLPROGRAM
            // 先 include 自己的输入（uniform 与 ForwardLit 相同），再复用 URP 的阴影投射 Pass（ShadowCasterPass.hlsl 的 GLSL 写法）
            #include "Ch10/MinimalLitInput.glsl"
            VARYING vec2 uv;
            #ifdef VERTEX
            void main()   // ShadowPassVertex
            {
                uv = TransformTex(texcoord0.xy, _BaseMap_ST);
                gl_Position = GetShadowPositionHClip(positionOS.xyz, normalOS);
            }
            #endif
            #ifdef FRAGMENT
            void main()   // ShadowPassFragment
            {
                Alpha(SampleAlbedoAlpha(uv).a, _BaseColor, _Cutoff);
                fragColor = vec4(0.0);
            }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R

            GLSLPROGRAM
            #include "Ch10/MinimalLitInput.glsl"
            VARYING vec2 uv;
            #ifdef VERTEX
            void main()   // DepthOnlyVertex
            {
                uv = TransformTex(texcoord0.xy, _BaseMap_ST);
                gl_Position = TransformObjectToHClip(positionOS.xyz);
            }
            #endif
            #ifdef FRAGMENT
            void main()   // DepthOnlyFragment
            {
                Alpha(SampleAlbedoAlpha(uv).a, _BaseColor, _Cutoff);
                fragColor = vec4(gl_FragCoord.z);
            }
            #endif
            ENDGLSL
        }

        Pass
        {
            // 开了 SSAO（Depth Normals 模式）或其他需要 _CameraNormalsTexture 的功能时会用到
            Name "DepthNormals"
            Tags { "LightMode"="DepthNormals" }
            ZWrite On

            GLSLPROGRAM
            #pragma shader_feature_local _NORMALMAP
            #include "Ch10/MinimalLitInput.glsl"
            VARYING vec2 uv;
            VARYING vec3 normalWS;
            VARYING vec4 tangentWS;
            #ifdef VERTEX
            void main()   // DepthNormalsVertex（LitDepthNormalsPass.hlsl）
            {
                uv = TransformTex(texcoord0.xy, _BaseMap_ST);
                VertexNormalInputs n = GetVertexNormalInputs(normalOS, tangentOS);
                normalWS = n.normalWS;
                tangentWS = vec4(n.tangentWS, tangentOS.w * GetOddNegativeScale());
                gl_Position = TransformObjectToHClip(positionOS.xyz);
            }
            #endif
            #ifdef FRAGMENT
            void main()   // DepthNormalsFragment
            {
                Alpha(SampleAlbedoAlpha(uv).a, _BaseColor, _Cutoff);
            #ifdef _NORMALMAP
                vec3 nTS = SampleNormal(uv, _BumpScale);
                vec3 b = tangentWS.w * cross(normalWS, tangentWS.xyz);
                vec3 n = normalize(mat3(tangentWS.xyz, b, normalWS) * nTS);
            #else
                vec3 n = normalize(normalWS);
            #endif
                fragColor = vec4(n, 0.0);
            }
            #endif
            ENDGLSL
        }
        //#endregion
    }
}
