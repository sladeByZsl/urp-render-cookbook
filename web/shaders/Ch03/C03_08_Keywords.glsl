// 第 8 步：用关键字（Keyword）做功能开关 —— 一份源码，按需编译出多个变体。
// 这是本章的“完成版”：纹理、顶点色、Alpha Clip、雾、SRP Batcher、阴影、深度全部具备。
Shader "Cookbook/Ch03/Keywords"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        // CBUFFER_START(UnityPerMaterial)
        uniform vec4  _BaseMap_ST;
        uniform vec4  _BaseColor;
        uniform float _Cutoff;
        uniform float _WorldUVScale;
        // CBUFFER_END

        uniform sampler2D _BaseMap;

        //#region uv
        // 根据关键字选择 UV 来源。#if 在编译期决定，没被选中的分支根本不会进入这个变体
        vec2 ComputeUV(vec2 meshUV, vec3 positionWS)
        {
        #if defined(_UVSOURCE_WORLDXZ)
            vec2 uv = positionWS.xz * _WorldUVScale;   // 俯视投影：相邻物体的纹理无缝衔接
        #else
            vec2 uv = meshUV;
        #endif
            return TransformTex(uv, _BaseMap_ST);
        }

        #ifdef FRAGMENT
        void ClipByAlpha(vec2 uv)
        {
        #if defined(_ALPHATEST_ON)
            float a = texture(_BaseMap, uv).a * _BaseColor.a;
            if (a - _Cutoff < 0.0) discard;
        #endif
        }
        #endif
        //#endregion
        ENDGLSL

        Pass
        {
            Name "Unlit"
            // 不需要 GBuffer 的 Unlit：用 UniversalForwardOnly，Forward / Forward+ / Deferred 三种路径都会画它
            Tags { "LightMode"="UniversalForwardOnly" }
            Cull [_Cull]

            GLSLPROGRAM
            //#region pragmas
            // 材质开关：shader_feature —— 只编译“有材质用到”的组合；_local 不占用全局关键字名额
            #pragma shader_feature_local _VERTEX_COLOR_ON
            #pragma shader_feature_local_fragment _ALPHATEST_ON
            #pragma shader_feature_local _UVSOURCE_MESH _UVSOURCE_WORLDXZ
            // 全局开关：multi_compile —— 运行时可能切换，所有组合都要编译进包
            #pragma multi_compile_fog
            //#endregion

            VARYING vec2 uv;
            VARYING float fogFactor;
        #if defined(_VERTEX_COLOR_ON)
            VARYING vec4 vColor;      // 不用顶点色的变体连插值器都省掉
        #endif

            #ifdef VERTEX
            void main()
            {
                VertexPositionInputs pos = GetVertexPositionInputs(positionOS.xyz);
                gl_Position = pos.positionCS;
                uv = ComputeUV(texcoord0.xy, pos.positionWS);
                fogFactor = ComputeFogFactor(pos.positionCS.z);
            #if defined(_VERTEX_COLOR_ON)
                vColor = color;
            #endif
            }
            #endif

            //#region frag
            #ifdef FRAGMENT
            void main()
            {
                vec4 tex = texture(_BaseMap, uv);
            #if defined(_ALPHATEST_ON)
                if (tex.a * _BaseColor.a - _Cutoff < 0.0) discard;
            #endif
                vec3 rgb = tex.rgb * _BaseColor.rgb;
            #if defined(_VERTEX_COLOR_ON)
                rgb *= vColor.rgb;
            #endif
                rgb = MixFog(rgb, fogFactor);
                fragColor = vec4(rgb, 1);
            }
            #endif
            //#endregion
            ENDGLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull [_Cull]

            GLSLPROGRAM
            #pragma shader_feature_local _ALPHATEST_ON
            #pragma shader_feature_local _UVSOURCE_MESH _UVSOURCE_WORLDXZ
            // _CASTING_PUNCTUAL_LIGHT_SHADOW 在网页版是 uniform _CastingPunctualLightShadow；ApplyShadowBias 等由 Lighting.glsl 提供

            VARYING vec2 uv;

            #ifdef VERTEX
            void main()
            {
                vec3 positionWS = TransformObjectToWorld(positionOS.xyz);
                vec3 normalWS   = TransformObjectToWorldNormal(normalOS);
                vec3 lightDirectionWS = _CastingPunctualLightShadow > 0.5
                    ? normalize(_LightPosition - positionWS)
                    : _LightDirection;
                gl_Position = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS));
            #if UNITY_REVERSED_Z
                gl_Position.z = min(gl_Position.z, UNITY_NEAR_CLIP_VALUE);
            #else
                gl_Position.z = max(gl_Position.z, UNITY_NEAR_CLIP_VALUE);
            #endif
                uv = ComputeUV(texcoord0.xy, positionWS);
            }
            #endif

            #ifdef FRAGMENT
            void main()
            {
                ClipByAlpha(uv);
                fragColor = vec4(0.0);
            }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On
            ColorMask R
            Cull [_Cull]

            GLSLPROGRAM
            #pragma shader_feature_local _ALPHATEST_ON
            #pragma shader_feature_local _UVSOURCE_MESH _UVSOURCE_WORLDXZ

            VARYING vec2 uv;

            #ifdef VERTEX
            void main()
            {
                vec3 positionWS = TransformObjectToWorld(positionOS.xyz);
                gl_Position = TransformWorldToHClip(positionWS);
                uv = ComputeUV(texcoord0.xy, positionWS);
            }
            #endif

            #ifdef FRAGMENT
            void main()
            {
                ClipByAlpha(uv);
                fragColor = vec4(gl_FragCoord.z);
            }
            #endif
            ENDGLSL
        }
    }
}
