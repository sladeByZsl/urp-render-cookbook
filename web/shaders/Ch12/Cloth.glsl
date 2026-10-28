// 布料：Charlie sheen 法线分布 + Neubelt 可见性 + 包裹漫反射与次表面色（Filament 布料模型的思路）。
// （GLSL 版，对应 Ch12/Cloth.shader）
Shader "Cookbook/Ch12/Cloth"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform vec4  _BaseColor, _SheenColor, _SubsurfaceColor;
        uniform float _Smoothness, _SheenRoughness, _Wrap;
        uniform float _WeaveScale;
        uniform float _WeaveStrength;
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }

            GLSLPROGRAM
            #pragma shader_feature_local_fragment _MODEL_GGX _MODEL_CHARLIE _MODEL_SUBSURFACE

            #include "Ch12/Ch12Common.glsl"

            #ifdef VERTEX
            void main() { Ch12Vert(); }
            #endif

            #ifdef FRAGMENT
            struct MaterialCtx
            {
                vec3 N, V;
                vec3 albedo, sheen;
                float a;          // GGX 用的 α
                float sheenA;     // Charlie 用的 α
            };

            //#region shade
            vec3 ShadeOneLight(MaterialCtx m, Light light)
            {
                vec3 L = light.direction;
                vec3 H = normalize(m.V + L);
                float NoLu = dot(m.N, L);
                float NoL = saturate(NoLu);
                float NoV = max(dot(m.N, m.V), 1e-4);
                float NoH = saturate(dot(m.N, H));
                float atten = light.distanceAttenuation * light.shadowAttenuation;

            #if defined(_MODEL_GGX)
                // 对照组：把布当成普通电介质
                vec3 brdf = m.albedo * ADV_INV_PI + AdvSpecularGGX(m.N, m.V, L, m.a, 0.04);
                return brdf * PI * light.color * (NoL * atten);
            #else
                // 镜面：Charlie 分布 × Neubelt 可见性 × sheen 颜色（布料没有明显的菲涅尔变化，直接用颜色当 F）
                vec3 Fr = AdvD_Charlie(NoH, m.sheenA) * AdvV_Neubelt(NoV, NoL) * m.sheen;
              #if defined(_MODEL_SUBSURFACE)
                // 漫反射：包裹 + 次表面色，光“渗”进暗部并带上颜色
                vec3 Fd = m.albedo * ADV_INV_PI * AdvWrapDiffuse(NoLu, _Wrap);
                Fd *= saturate(_SubsurfaceColor.rgb + NoL);
                return (Fd + Fr * NoL) * PI * light.color * atten;
              #else
                vec3 Fd = m.albedo * ADV_INV_PI;
                return (Fd + Fr) * PI * light.color * (NoL * atten);
              #endif
            #endif
            }
            //#endregion

            #include "Ch12/LightLoop.glsl"

            void main()
            {
                vec3 T, B, N; Ch12BuildFrame(T, B, N);
                vec3 V = GetWorldSpaceNormalizeViewDir(positionWS);
                vec2 screenUV = GetNormalizedScreenSpaceUV(gl_FragCoord);
                float NoV = saturate(dot(N, V));

                //#region weave
                // 程序化平纹：经纬线交替压在上面，用两组正弦的乘积近似线的明暗
                vec2 w = uv * _WeaveScale;
                float warp = abs(sin(w.x * PI)) * step(0.5, fract(w.y * 0.5 + floor(w.x) * 0.5));
                float weft = abs(sin(w.y * PI)) * (1.0 - step(0.5, fract(w.y * 0.5 + floor(w.x) * 0.5)));
                float thread = saturate(warp + weft);
                float weave = mix(1.0, mix(0.7, 1.1, thread), _WeaveStrength);
                //#endregion

                MaterialCtx m;
                m.N = N; m.V = V;
                m.albedo = _BaseColor.rgb * weave;
                m.sheen = _SheenColor.rgb * weave;
                float pr = 1.0 - _Smoothness;
                m.a = max(pr * pr, 0.002);
                m.sheenA = max(_SheenRoughness * _SheenRoughness, 0.01);

                vec3 color = AccumulateDirectLighting(m, positionWS, screenUV);

                // 间接光
                color += SampleSH(N) * m.albedo;
            #if defined(_MODEL_GGX)
                vec2 AB = AdvEnvBRDFApprox(pr, NoV);
                color += GlossyEnvironmentReflection(reflect(-V, N), positionWS, pr, 1.0) * (0.04 * AB.x + AB.y);
            #else
                // 环境 sheen：严格做法是像 split-sum 那样把 D_Charlie·V_Neubelt 预积分成 LUT；
                // 这里用一个随掠射角增强的经验系数代替，够用且便宜
                float sheenEnv = mix(0.12, 0.35, _SheenRoughness) * (0.4 + 0.6 * pow(1.0 - NoV, 2.0));
                color += GlossyEnvironmentReflection(reflect(-V, N), positionWS, _SheenRoughness, 1.0) * m.sheen * sheenEnv;
            #endif

                color = MixFog(color, fogFactor);
                fragColor = vec4(color, 1.0);
            }
            #endif
            ENDGLSL
        }

        UsePass "Cookbook/Common/SHADOWCASTER"
        UsePass "Cookbook/Common/DEPTHONLY"
        UsePass "Cookbook/Common/DEPTHNORMALS"
    }
}
