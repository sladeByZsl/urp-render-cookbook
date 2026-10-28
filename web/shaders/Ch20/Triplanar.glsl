// 案例 20.2 / 20.3：完整的三平面映射——颜色 + 法线（四种法线混合方式可切换）（GLSL 版，对应 Ch20/Triplanar.shader）
Shader "Cookbook/Ch20/Triplanar"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform vec4 _BaseMap_ST;
        uniform vec4 _BaseColor;
        uniform float _BumpScale;
        uniform float _Tiling;
        uniform float _Sharpness;
        uniform float _NormalMode;
        uniform float _Smoothness;
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }   // 自定义表面混合，没有 GBuffer Pass：Deferred 下也走前向
            GLSLPROGRAM
            #pragma multi_compile_fog
            #pragma multi_compile_instancing

            #include "Ch20/TerrainCommon.glsl"

            uniform sampler2D _BaseMap;
            uniform sampler2D _BumpMap;

            VARYING vec3 positionWS;
            VARYING vec3 normalWS;
            VARYING float fogFactor;

            #ifdef VERTEX
            void main()
            {
                VertexPositionInputs p = GetVertexPositionInputs(positionOS.xyz);
                gl_Position = p.positionCS;
                positionWS = p.positionWS;
                normalWS = TransformObjectToWorldNormal(normalOS);
                fogFactor = ComputeFogFactor(p.positionCS.z);
            }
            #endif

            #ifdef FRAGMENT
            //#region frag
            vec4 frag()
            {
                vec3 n = normalize(normalWS);
                vec3 w = TriplanarWeights(n, _Sharpness);
                TriplanarUV uv = GetTriplanarUV(positionWS, n, _Tiling);

                vec3 albedo = SampleTriplanar(_BaseMap, uv, w).rgb * _BaseColor.rgb;
                vec3 nWS = TriplanarNormalWS(_BumpMap, uv, w, n, _BumpScale, int(_NormalMode));

                return Ch20ShadePBR(positionWS, nWS, gl_FragCoord, albedo, 0.0, _Smoothness, 1.0, fogFactor);
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
