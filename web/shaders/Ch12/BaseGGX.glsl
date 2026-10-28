// 第 12 章的“基准材质”：自己实现的 GGX 金属度工作流。
// 后面所有进阶材质都在它的基础上增加一层或替换某一项，所以先拿它和 URP Lit 对一下数。
// （GLSL 版，对应 Ch12/BaseGGX.shader）
Shader "Cookbook/Ch12/BaseGGX"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform vec4  _BaseMap_ST;
        uniform vec4  _BaseColor;
        uniform float _Metallic;
        uniform float _Smoothness;
        uniform sampler2D _BaseMap;
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }

            GLSLPROGRAM
            #include "Ch12/Ch12Common.glsl"

            #ifdef VERTEX
            void main() { Ch12Vert(); }
            #endif

            #ifdef FRAGMENT
            //#region shade
            struct MaterialCtx
            {
                vec3 N, V;
                vec3 diffuse;   // 漫反射颜色（已扣掉金属部分）
                vec3 f0;        // 法向入射反射率
                float a;        // α = 感知粗糙度²
            };

            // URP 的灯光约定：color 已经是“除过 π 的辐照度”，所以 BRDF 要整体乘 π
            vec3 ShadeOneLight(MaterialCtx m, Light light)
            {
                float NoL = saturate(dot(m.N, light.direction));
                vec3 brdf = m.diffuse * ADV_INV_PI + AdvSpecularGGX(m.N, m.V, light.direction, m.a, m.f0);
                return brdf * PI * light.color * (NoL * light.distanceAttenuation * light.shadowAttenuation);
            }
            //#endregion

            #include "Ch12/LightLoop.glsl"

            //#region frag
            void main()
            {
                vec3 T, B, N; Ch12BuildFrame(T, B, N);
                vec3 V = GetWorldSpaceNormalizeViewDir(positionWS);
                vec2 screenUV = GetNormalizedScreenSpaceUV(gl_FragCoord);

                vec4 albedo = texture(_BaseMap, TransformTex(uv, _BaseMap_ST)) * _BaseColor;
                float perceptualRoughness = 1.0 - _Smoothness;

                MaterialCtx m;
                m.N = N; m.V = V;
                m.f0 = mix(vec3(0.04), albedo.rgb, _Metallic);
                m.diffuse = albedo.rgb * (1.0 - _Metallic) * 0.96;
                m.a = max(perceptualRoughness * perceptualRoughness, 0.002);

                vec3 color = AccumulateDirectLighting(m, positionWS, screenUV);

                // 间接光：漫反射用球谐，镜面用反射探针 + 环境 BRDF 近似
                float NoV = saturate(dot(N, V));
                vec3 R = reflect(-V, N);
                vec2 AB = AdvEnvBRDFApprox(perceptualRoughness, NoV);
                color += SampleSH(N) * m.diffuse;
                color += GlossyEnvironmentReflection(R, positionWS, perceptualRoughness, 1.0) * (m.f0 * AB.x + AB.y);

                color = MixFog(color, fogFactor);
                fragColor = vec4(color, 1.0);
            }
            //#endregion
            #endif
            ENDGLSL
        }

        //#region passes
        // 投影 / 深度 / 深度法线：HLSL 版直接复用 URP 自带的 Pass，网页版用公共的同功能 Pass
        UsePass "Cookbook/Common/SHADOWCASTER"
        UsePass "Cookbook/Common/DEPTHONLY"
        UsePass "Cookbook/Common/DEPTHNORMALS"
        //#endregion
    }
}
