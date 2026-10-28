// 案例 20.1：同一张贴图的三种贴法——网格 UV、世界空间 XZ 平面投影、三平面投影（GLSL 版，对应 Ch20/UVCompare.shader）
Shader "Cookbook/Ch20/UVCompare"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        // 所有 Pass 共用同一份材质参数
        GLSLINCLUDE
        uniform vec4 _BaseMap_ST;
        uniform float _Tiling;
        uniform float _Sharpness;
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }   // 自定义表面混合，没有 GBuffer Pass：Deferred 下也走前向
            GLSLPROGRAM
            #pragma shader_feature_local_fragment _UVMODE_MESHUV _UVMODE_WORLDXZ _UVMODE_TRIPLANAR _UVMODE_WEIGHTS
            #pragma multi_compile_fog
            #pragma multi_compile_instancing

            #include "Ch20/TerrainCommon.glsl"

            uniform sampler2D _BaseMap;

            VARYING vec3 positionWS;
            VARYING vec3 normalWS;
            VARYING vec2 uv;
            VARYING float fogFactor;

            #ifdef VERTEX
            void main()
            {
                VertexPositionInputs p = GetVertexPositionInputs(positionOS.xyz);
                gl_Position = p.positionCS;
                positionWS = p.positionWS;
                normalWS = TransformObjectToWorldNormal(normalOS);
                uv = TransformTex(texcoord0.xy, _BaseMap_ST);
                fogFactor = ComputeFogFactor(p.positionCS.z);
            }
            #endif

            #ifdef FRAGMENT
            //#region frag
            vec4 frag()
            {
                vec3 n = normalize(normalWS);
                vec3 albedo;
            #if defined(_UVMODE_MESHUV)
                albedo = texture(_BaseMap, uv).rgb;
            #elif defined(_UVMODE_WORLDXZ)
                // 世界空间 UV：从正上方往下“投影”，平地完美，陡坡被拉成竖条
                albedo = texture(_BaseMap, positionWS.xz * _Tiling).rgb;
            #else
                vec3 w = TriplanarWeights(n, _Sharpness);
                #if defined(_UVMODE_WEIGHTS)
                    albedo = w;     // 调试：R=X 投影 G=Y 投影 B=Z 投影
                #else
                    TriplanarUV tuv = GetTriplanarUV(positionWS, n, _Tiling);
                    albedo = SampleTriplanar(_BaseMap, tuv, w).rgb;
                #endif
            #endif
                return Ch20ShadePBR(positionWS, n, gl_FragCoord, albedo, 0.0, 0.15, 1.0, fogFactor);
            }
            //#endregion
            void main() { fragColor = frag(); }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0
            GLSLPROGRAM
            #pragma multi_compile_instancing
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #define CH20_SHADOW_PASS
            #include "Ch20/ShadowDepthPasses.glsl"
            ENDGLSL
        }
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            GLSLPROGRAM
            #pragma multi_compile_instancing
            #define CH20_DEPTH_PASS
            #include "Ch20/ShadowDepthPasses.glsl"
            ENDGLSL
        }
        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode"="DepthNormals" }
            ZWrite On
            GLSLPROGRAM
            #pragma multi_compile_instancing
            #define CH20_DEPTHNORMALS_PASS
            #include "Ch20/ShadowDepthPasses.glsl"
            ENDGLSL
        }
    }
}
