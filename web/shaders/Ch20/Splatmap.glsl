// 案例 20.6：四层 Splatmap 混合（仿 URP TerrainLit 的数据布局：_Control 的 RGBA 是四层权重）（GLSL 版，对应 Ch20/Splatmap.shader）
Shader "Cookbook/Ch20/Splatmap"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform vec4 _SplatTiling;
        uniform float _HeightTransition;
        uniform float _HeightBased;
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }   // 自定义表面混合，没有 GBuffer Pass：Deferred 下也走前向
            GLSLPROGRAM
            #pragma shader_feature_local_fragment _DEBUG_CONTROL
            #pragma multi_compile_fog
            #pragma multi_compile_instancing

            #include "Ch20/TerrainCommon.glsl"

            uniform sampler2D _Control;
            uniform sampler2D _Splat0;   // HLSL 版四层共用 sampler_Splat0（与 TerrainLit 一样）；GLSL 每张图自带采样状态
            uniform sampler2D _Splat1;
            uniform sampler2D _Splat2;
            uniform sampler2D _Splat3;
            uniform sampler2D _Normal2;

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
                uv = texcoord0.xy;
                fogFactor = ComputeFogFactor(p.positionCS.z);
            }
            #endif

            #ifdef FRAGMENT
            //#region heightSplat
            // 与 TerrainLit 的 HeightBasedSplatModify 同一思路：
            // 高度 × 权重，取最高者，比它低 transition 以上的层直接归零，剩下的重新归一化
            vec4 HeightBasedSplat(vec4 control, vec4 heights, float transition)
            {
                vec4 h = heights * control;
                float maxH = max(max(h.r, h.g), max(h.b, h.a));
                vec4 w = max(h + max(transition, 1e-5) - maxH, 0.0);
                w = (w + 1e-6) * control;                  // 权重为 0 的层永远不出现
                return w / max(dot(w, vec4(1.0)), 1e-6);
            }
            //#endregion

            //#region frag
            vec4 frag()
            {
                vec3 n = normalize(normalWS);
                vec4 control = texture(_Control, uv);
                control /= max(dot(control, vec4(1.0)), 1e-4);   // 画笔刷出来的权重不一定和为 1

            #if defined(_DEBUG_CONTROL)
                vec3 dbg = control.r * vec3(0.2, 0.7, 0.15) + control.g * vec3(0.85, 0.6, 0.25)
                         + control.b * vec3(0.6, 0.6, 0.65) + control.a * vec3(1, 1, 1);
                return vec4(dbg * (0.55 + 0.45 * saturate(dot(n, vec3(0.3, 0.9, -0.3)))), 1.0);
            #endif

                vec2 xz = positionWS.xz;
                vec4 s0 = texture(_Splat0, xz * _SplatTiling.x);
                vec4 s1 = texture(_Splat1, xz * _SplatTiling.y);
                vec4 s3 = texture(_Splat3, xz * _SplatTiling.w);
                // 第 2 层是岩石，崖壁上用 Triplanar（TerrainLit 本身没有这一步）
                vec3 tw = TriplanarWeights(n, 8.0);
                TriplanarUV tuv = GetTriplanarUV(positionWS, n, _SplatTiling.z);
                vec4 s2 = SampleTriplanar(_Splat2, tuv, tw);
                vec3 rockN = TriplanarNormalWS(_Normal2, tuv, tw, n, 1.0, 3);

                if (_HeightBased > 0.5)
                    control = HeightBasedSplat(control, vec4(s0.a, s1.a, s2.a, s3.a), _HeightTransition);

                vec3 albedo = s0.rgb * control.r + s1.rgb * control.g + s2.rgb * control.b + s3.rgb * control.a;
                vec3 nWS = normalize(mix(n, rockN, control.b));
                float smoothness = dot(control, vec4(0.1, 0.15, 0.25, 0.5));
                return Ch20ShadePBR(positionWS, nWS, gl_FragCoord, albedo, 0.0, smoothness, 1.0, fogFactor);
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
