// 第 24 章：与“Lit Graph 溶解”等价的手写 Shader（GLSL 版）。
// Lit Graph 的 Master Stack 输出 Base Color / Metallic / Smoothness / Emission / Alpha / Alpha Clip Threshold，
// 生成代码最终把它们填进 SurfaceData 再调用 UniversalFragmentPBR —— 这里照做一遍。
Shader "Cookbook/Ch24/SGDissolveEquivalent"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="AlphaTest" }

        GLSLINCLUDE
        #include "Ch24/StylizedFunctions.glsl"
        uniform vec4  _BaseColor;
        uniform float _Metallic;
        uniform float _Smoothness;
        uniform vec4  _NoiseMap_ST;
        uniform float _Progress;
        uniform float _EdgeWidth;
        uniform vec4  _EdgeColor;
        uniform sampler2D _NoiseMap;

        // 图里“Sample Texture 2D → Dissolve”这一段，所有 Pass 共用
        void DissolveGraph(vec2 uv, out float alpha, out float edge)
        {
            float noise = texture(_NoiseMap, TransformTex(uv, _NoiseMap_ST)).r;
            Dissolve_float(noise, _Progress, _EdgeWidth, alpha, edge);
        }
        ENDGLSL

        Pass
        {
            Name "Universal Forward"
            Tags { "LightMode"="UniversalForward" }
            GLSLPROGRAM
            VARYING vec2 uv;
            VARYING vec3 positionWS;
            VARYING vec3 normalWS;

            #ifdef VERTEX
            void main()
            {
                VertexPositionInputs p = GetVertexPositionInputs(positionOS.xyz);
                gl_Position = p.positionCS; positionWS = p.positionWS;
                normalWS = TransformObjectToWorldNormal(normalOS);
                uv = texcoord0.xy;
            }
            #endif

            #ifdef FRAGMENT
            //#region frag
            vec4 frag()
            {
                float alpha, edge;
                DissolveGraph(uv, alpha, edge);
                if (alpha - 0.5 < 0.0) discard;              // Alpha Clip Threshold = 0.5

                SurfaceData surface = InitSurfaceData();     // ← Master Stack 的各个 Block
                surface.albedo     = _BaseColor.rgb * (1.0 - edge);
                surface.metallic   = _Metallic;
                surface.smoothness = _Smoothness;
                surface.occlusion  = 1.0;
                surface.emission   = edge * _EdgeColor.rgb;
                surface.alpha      = 1.0;
                surface.normalTS   = vec3(0, 0, 1);

                InputData inputData = InitInputData();
                inputData.positionWS = positionWS;
                inputData.normalWS = normalize(normalWS);
                inputData.viewDirectionWS = GetWorldSpaceNormalizeViewDir(positionWS);
                inputData.shadowCoord = TransformWorldToShadowCoord(positionWS);
                inputData.bakedGI = SampleSH(inputData.normalWS);
                inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(gl_FragCoord);
                inputData.shadowMask = vec4(1, 1, 1, 1);
                return UniversalFragmentPBR(inputData, surface);
            }
            //#endregion
            void main() { fragColor = frag(); }
            #endif
            ENDGLSL
        }

        //#region caster
        Pass
        {
            // Shader Graph 会自动把 Alpha Clip 带进 ShadowCaster / DepthOnly；手写时最容易忘
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0
            GLSLPROGRAM
            #include "Ch23/Ch23Common.glsl"
            VARYING vec2 uv;
            #ifdef VERTEX
            void main()
            {
                gl_Position = Ch23ShadowCasterVert();
                uv = texcoord0.xy;
            }
            #endif
            #ifdef FRAGMENT
            void main()
            {
                float alpha, edge;
                DissolveGraph(uv, alpha, edge);
                if (alpha - 0.5 < 0.0) discard;
                fragColor = vec4(0.0);
            }
            #endif
            ENDGLSL
        }
        //#endregion

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            GLSLPROGRAM
            VARYING vec2 uv;
            #ifdef VERTEX
            void main() { gl_Position = TransformObjectToHClip(positionOS.xyz); uv = texcoord0.xy; }
            #endif
            #ifdef FRAGMENT
            void main()
            {
                float alpha, edge;
                DissolveGraph(uv, alpha, edge);
                if (alpha - 0.5 < 0.0) discard;
                fragColor = vec4(gl_FragCoord.z);
            }
            #endif
            ENDGLSL
        }
    }
}
