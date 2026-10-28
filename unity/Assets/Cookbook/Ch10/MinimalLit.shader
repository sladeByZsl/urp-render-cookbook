// 第 10 章：最小 Lit。
// 自己准备 SurfaceData 和 InputData，然后直接调用 URP 的 UniversalFragmentPBR —— 光照结果与 URP Lit 一致，
// 但代码量只有 Lit 的一小部分，便于看清“喂给 PBR 的到底是什么”。
// 省略了：光照贴图、视差、细节贴图、Mask Map、透明、清漆、Decal、Light Cookie、Rendering Layers、Debug Display。
Shader "Cookbook/Ch10/MinimalLit"
{
    Properties
    {
        [MainTexture] _BaseMap("Base Map", 2D) = "white" {}
        [MainColor] _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        _Metallic("Metallic", Range(0, 1)) = 0
        _Smoothness("Smoothness", Range(0, 1)) = 0.5
        [Normal][NoScaleOffset] _BumpMap("Normal Map", 2D) = "bump" {}
        _BumpScale("Normal Scale", Float) = 1
        [HDR] _EmissionColor("Emission", Color) = (0, 0, 0, 1)
        [HideInInspector] _Cutoff("Alpha Cutoff", Range(0, 1)) = 0.5
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "UniversalMaterialType"="Lit" "Queue"="Geometry" }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma target 2.0
            #pragma vertex vert
            #pragma fragment frag

            //#region keywords
            // 材质关键字：有法线贴图才开（脚本创建材质时要自己 EnableKeyword）
            #pragma shader_feature_local _NORMALMAP
            // 管线关键字：与 URP 14 Lit.shader 保持同名，管线会按设置自动打开
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BLENDING
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BOX_PROJECTION
            #pragma multi_compile_fragment _ _SCREEN_SPACE_OCCLUSION
            #pragma multi_compile _ _FORWARD_PLUS
            #pragma multi_compile_fog
            #pragma multi_compile_instancing
            //#endregion

            #include "Assets/Cookbook/Ch10/MinimalLitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float4 tangentOS  : TANGENT;
                float2 uv         : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                half3  normalWS   : TEXCOORD2;
                half4  tangentWS  : TEXCOORD3;   // w = 副切线符号
                half   fogFactor  : TEXCOORD4;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            Varyings vert(Attributes v)
            {
                Varyings o = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, o);

                VertexPositionInputs pos = GetVertexPositionInputs(v.positionOS.xyz);
                VertexNormalInputs   nrm = GetVertexNormalInputs(v.normalOS, v.tangentOS);
                o.positionCS = pos.positionCS;
                o.positionWS = pos.positionWS;
                o.normalWS   = nrm.normalWS;
                o.tangentWS  = half4(nrm.tangentWS, v.tangentOS.w * GetOddNegativeScale());
                o.uv         = TRANSFORM_TEX(v.uv, _BaseMap);
                o.fogFactor  = ComputeFogFactor(pos.positionCS.z);
                return o;
            }

            //#region surface
            SurfaceData BuildSurfaceData(float2 uv)
            {
                SurfaceData s = (SurfaceData)0;
                half4 albedoAlpha = SampleAlbedoAlpha(uv, TEXTURE2D_ARGS(_BaseMap, sampler_BaseMap));
                s.albedo     = albedoAlpha.rgb * _BaseColor.rgb;
                s.alpha      = 1.0;                      // 不透明
                s.metallic   = _Metallic;                // 金属度工作流：specular 留 0
                s.specular   = 0;
                s.smoothness = _Smoothness;
                s.normalTS   = SampleNormal(uv, TEXTURE2D_ARGS(_BumpMap, sampler_BumpMap), _BumpScale);
                s.occlusion  = 1.0;
                s.emission   = _EmissionColor.rgb;
                s.clearCoatMask = 0;
                s.clearCoatSmoothness = 0;
                return s;
            }
            //#endregion

            //#region inputdata
            InputData BuildInputData(Varyings i, half3 normalTS)
            {
                InputData d = (InputData)0;
                d.positionWS = i.positionWS;
                d.positionCS = i.positionCS;

            #if defined(_NORMALMAP)
                float3 bitangent = i.tangentWS.w * cross(i.normalWS, i.tangentWS.xyz);
                d.tangentToWorld = half3x3(i.tangentWS.xyz, bitangent, i.normalWS);
                d.normalWS = TransformTangentToWorld(normalTS, d.tangentToWorld);
            #else
                d.normalWS = i.normalWS;
            #endif
                d.normalWS = NormalizeNormalPerPixel(d.normalWS);
                d.viewDirectionWS = GetWorldSpaceNormalizeViewDir(i.positionWS);

                d.shadowCoord = TransformWorldToShadowCoord(i.positionWS);   // 逐像素算级联，省一个插值器
                d.fogCoord = i.fogFactor;
                d.vertexLighting = 0;
                d.bakedGI = SampleSH(d.normalWS);                            // 无光照贴图：逐像素 SH
                d.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(i.positionCS);
                d.shadowMask = half4(1, 1, 1, 1);
                return d;
            }
            //#endregion

            //#region frag
            half4 frag(Varyings i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                SurfaceData surfaceData = BuildSurfaceData(i.uv);
                InputData inputData = BuildInputData(i, surfaceData.normalTS);

                half4 color = UniversalFragmentPBR(inputData, surfaceData);
                color.rgb = MixFog(color.rgb, inputData.fogCoord);
                return color;
            }
            //#endregion
            ENDHLSL
        }

        //#region shadowpass
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0

            HLSLPROGRAM
            #pragma target 2.0
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment
            #pragma multi_compile_instancing
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            // 先 include 自己的输入（CBUFFER 与 ForwardLit 相同），再直接复用 URP 的阴影投射 Pass
            #include "Assets/Cookbook/Ch10/MinimalLitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R

            HLSLPROGRAM
            #pragma target 2.0
            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment
            #pragma multi_compile_instancing
            #include "Assets/Cookbook/Ch10/MinimalLitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/DepthOnlyPass.hlsl"
            ENDHLSL
        }

        Pass
        {
            // 开了 SSAO（Depth Normals 模式）或其他需要 _CameraNormalsTexture 的功能时会用到
            Name "DepthNormals"
            Tags { "LightMode"="DepthNormals" }
            ZWrite On

            HLSLPROGRAM
            #pragma target 2.0
            #pragma vertex DepthNormalsVertex
            #pragma fragment DepthNormalsFragment
            #pragma shader_feature_local _NORMALMAP
            #pragma multi_compile_instancing
            #include "Assets/Cookbook/Ch10/MinimalLitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitDepthNormalsPass.hlsl"
            ENDHLSL
        }
        //#endregion
    }
}
