// 案例 20.5：线性混合 vs 高度混合——砖地上长出的草先填满砖缝（GLSL 版，对应 Ch20/HeightBlend.shader）
Shader "Cookbook/Ch20/HeightBlend"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform vec4 _MapA_ST;
        uniform float _TilingB;
        uniform float _MaskContrast, _MaskOffset, _UseHeight, _BlendDepth;
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }   // 自定义表面混合，没有 GBuffer Pass：Deferred 下也走前向
            GLSLPROGRAM
            #pragma multi_compile_fog
            #pragma multi_compile_instancing

            #include "Ch20/TerrainCommon.glsl"

            uniform sampler2D _MapA;
            uniform sampler2D _HeightA;
            uniform sampler2D _NormalA;
            uniform sampler2D _MapB;
            uniform sampler2D _NoiseTex;

            VARYING vec3 positionWS;
            VARYING vec3 normalWS;
            VARYING vec4 tangentWS;
            VARYING vec2 uv;
            VARYING float fogFactor;

            #ifdef VERTEX
            void main()
            {
                VertexPositionInputs p = GetVertexPositionInputs(positionOS.xyz);
                VertexNormalInputs nI = GetVertexNormalInputs(normalOS, tangentOS);
                gl_Position = p.positionCS;
                positionWS = p.positionWS;
                normalWS = nI.normalWS;
                tangentWS = vec4(nI.tangentWS, tangentOS.w * GetOddNegativeScale());
                uv = texcoord0.xy;
                fogFactor = ComputeFogFactor(p.positionCS.z);
            }
            #endif

            #ifdef FRAGMENT
            //#region frag
            vec4 frag()
            {
                vec2 uvA = TransformTex(uv, _MapA_ST);
                vec2 uvB = uv * _TilingB;
                vec3 albedoA = texture(_MapA, uvA).rgb;
                float heightA = texture(_HeightA, uvA).r;
                vec3 normalA = UnpackNormalmapRGorAG(texture(_NormalA, uvA), 1.0);   // = URP 桌面平台的 UnpackNormal
                vec4 layerB  = texture(_MapB, uvB);

                // 遮罩：从左到右的渐变 + 噪声，模拟“刷”出来的过渡区
                float noise = texture(_NoiseTex, uv * 1.5).r - 0.5;
                float mask = saturate((uv.x - 0.5 + _MaskOffset + noise * 0.35) * _MaskContrast + 0.5);

                // 线性混合 vs 高度混合
                float tLinear = mask;
                float tHeight = HeightBlendWeight(heightA, layerB.a, mask, _BlendDepth);
                float t = mix(tLinear, tHeight, _UseHeight);

                vec3 albedo = mix(albedoA, layerB.rgb, t);
                vec3 normalTS = normalize(mix(normalA, vec3(0, 0, 1), t));
                float sgn = tangentWS.w;
                vec3 bitangent = sgn * cross(normalWS, tangentWS.xyz);
                // HLSL 的 half3x3(T, B, N) 按行构造；GLSL 的 mat3(T, B, N) 列就是 T/B/N，TransformTangentToWorld 已按此处理
                vec3 nWS = TransformTangentToWorld(normalTS, mat3(tangentWS.xyz, bitangent, normalWS));
                float occlusion = mix(mix(0.6, 1.0, heightA), 1.0, t);   // 砖缝顺手压暗一点
                return Ch20ShadePBR(positionWS, nWS, gl_FragCoord, albedo, 0.0, mix(0.3, 0.12, t), occlusion, fogFactor);
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
    }
}
