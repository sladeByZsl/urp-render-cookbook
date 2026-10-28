// URP 的 Lit 着色器（Lit.shader + LitForwardPass.hlsl）的 GLSL 版本：金属/高光两种工作流、法线贴图、AO、自发光、透明与裁剪。
Shader "Universal Render Pipeline/Lit"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" }
        GLSLINCLUDE
        #include "URP/LitInput.glsl"
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }
            Blend [_SrcBlend] [_DstBlend]
            ZWrite [_ZWrite]
            Cull [_Cull]
            GLSLPROGRAM
            #pragma shader_feature_local _NORMALMAP
            #pragma shader_feature_local _PARALLAXMAP
            #pragma shader_feature_local_fragment _SURFACE_TYPE_TRANSPARENT
            #pragma shader_feature_local_fragment _ALPHATEST_ON
            #pragma shader_feature_local_fragment _ALPHAPREMULTIPLY_ON
            #pragma shader_feature_local_fragment _EMISSION
            #pragma shader_feature_local_fragment _METALLICSPECGLOSSMAP
            #pragma shader_feature_local_fragment _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
            #pragma shader_feature_local_fragment _OCCLUSIONMAP
            #pragma shader_feature_local_fragment _SPECULARHIGHLIGHTS_OFF
            #pragma shader_feature_local_fragment _ENVIRONMENTREFLECTIONS_OFF
            #pragma shader_feature_local_fragment _SPECULAR_SETUP
            #pragma shader_feature_local _RECEIVE_SHADOWS_OFF

            VARYING vec2 uv;
            VARYING vec3 positionWS;
            VARYING vec3 normalWS;
            VARYING vec4 tangentWS;    // w = 副切线符号
            VARYING float fogFactor;

            #ifdef VERTEX
            void main()
            {
                VertexPositionInputs vertexInput = GetVertexPositionInputs(positionOS.xyz);
                VertexNormalInputs normalInput = GetVertexNormalInputs(normalOS, tangentOS);
                uv = TransformTex(texcoord0.xy, _BaseMap_ST);
                positionWS = vertexInput.positionWS;
                normalWS = normalInput.normalWS;
                float sign = tangentOS.w * GetOddNegativeScale();
                tangentWS = vec4(normalInput.tangentWS, sign);
                fogFactor = ComputeFogFactor(vertexInput.positionCS.z);
                gl_Position = vertexInput.positionCS;
            }
            #endif

            #ifdef FRAGMENT
            void main()
            {
                vec2 uvP = uv;
            #ifdef _PARALLAXMAP
                // 视差贴图（URP ParallaxMapping.hlsl 的 ParallaxOffset1Step，高度读 G 通道）
                vec3 bt = tangentWS.w * cross(normalWS, tangentWS.xyz);
                vec3 viewDirTS = GetWorldSpaceNormalizeViewDir(positionWS) * mat3(tangentWS.xyz, bt, normalWS);
                float h = texture(_ParallaxMap, uvP).g * _Parallax - _Parallax * 0.5;
                vec3 pv = normalize(viewDirTS); pv.z += 0.42;
                uvP += h * (pv.xy / pv.z);
            #endif
                SurfaceData surfaceData = InitializeStandardLitSurfaceData(uvP);

                InputData inputData = InitInputData();
                inputData.positionWS = positionWS;
                vec3 viewDirWS = GetWorldSpaceNormalizeViewDir(positionWS);
            #ifdef _NORMALMAP
                vec3 bitangent = tangentWS.w * cross(normalWS, tangentWS.xyz);
                mat3 tangentToWorld = mat3(tangentWS.xyz, bitangent, normalWS);
                inputData.normalWS = normalize(TransformTangentToWorld(surfaceData.normalTS, tangentToWorld));
            #else
                inputData.normalWS = normalize(normalWS);
            #endif
                inputData.viewDirectionWS = viewDirWS;
            #ifdef _RECEIVE_SHADOWS_OFF
                inputData.shadowCoord = vec4(0.0);
            #else
                inputData.shadowCoord = TransformWorldToShadowCoord(positionWS);
            #endif
                inputData.fogCoord = fogFactor;
                inputData.bakedGI = SampleSH(inputData.normalWS);
                inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(gl_FragCoord);

                vec4 color = UniversalFragmentPBR(inputData, surfaceData);
                color.rgb = MixFog(color.rgb, inputData.fogCoord);
            #ifndef _SURFACE_TYPE_TRANSPARENT
                color.a = 1.0;
            #endif
                fragColor = color;
            }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0
            Cull [_Cull]
            GLSLPROGRAM
            #pragma shader_feature_local_fragment _ALPHATEST_ON
            #pragma shader_feature_local_fragment _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
            VARYING vec2 uv;
            #ifdef VERTEX
            void main()
            {
                uv = TransformTex(texcoord0.xy, _BaseMap_ST);
                gl_Position = GetShadowPositionHClip(positionOS.xyz, normalOS);
            }
            #endif
            #ifdef FRAGMENT
            void main()
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
            Cull [_Cull]
            GLSLPROGRAM
            #pragma shader_feature_local_fragment _ALPHATEST_ON
            VARYING vec2 uv;
            #ifdef VERTEX
            void main()
            {
                uv = TransformTex(texcoord0.xy, _BaseMap_ST);
                gl_Position = TransformObjectToHClip(positionOS.xyz);
            }
            #endif
            #ifdef FRAGMENT
            void main()
            {
                Alpha(SampleAlbedoAlpha(uv).a, _BaseColor, _Cutoff);
                fragColor = vec4(gl_FragCoord.z);
            }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode"="DepthNormals" }
            ZWrite On
            Cull [_Cull]
            GLSLPROGRAM
            #pragma shader_feature_local _NORMALMAP
            #pragma shader_feature_local_fragment _ALPHATEST_ON
            VARYING vec2 uv;
            VARYING vec3 normalWS;
            VARYING vec4 tangentWS;
            #ifdef VERTEX
            void main()
            {
                uv = TransformTex(texcoord0.xy, _BaseMap_ST);
                VertexNormalInputs n = GetVertexNormalInputs(normalOS, tangentOS);
                normalWS = n.normalWS;
                tangentWS = vec4(n.tangentWS, tangentOS.w * GetOddNegativeScale());
                gl_Position = TransformObjectToHClip(positionOS.xyz);
            }
            #endif
            #ifdef FRAGMENT
            void main()
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
    }
}
