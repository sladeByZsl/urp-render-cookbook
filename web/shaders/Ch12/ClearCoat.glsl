// 清漆（Clear Coat）：在基础 GGX 材质上再盖一层透明的电介质 GGX。
// 两层之间的能量分配、折射对底层的影响，是本案例要讲清的重点。
// （GLSL 版，对应 Ch12/ClearCoat.shader）
Shader "Cookbook/Ch12/ClearCoat"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform vec4  _BaseColor;
        uniform float _Metallic, _Smoothness;
        uniform float _FlakeDensity;
        uniform float _FlakeStrength;
        uniform float _CoatMask, _CoatSmoothness, _CoatEnergy, _CoatAffectBase;
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
            //#region ctx
            struct MaterialCtx
            {
                vec3 N, V;
                vec3 flakeN;      // 带金属片扰动的底层法线
                vec3 diffuse, f0;
                float aBase;      // 底层 α（可能已被清漆修正）
                float aCoat;      // 清漆层 α
                float coatMask;
                float coatFv;     // 清漆在视线方向的菲涅尔，用来衰减底层
            };
            //#endregion

            //#region shade
            vec3 ShadeOneLight(MaterialCtx m, Light light)
            {
                vec3 L = light.direction;
                vec3 H = normalize(m.V + L);
                float NoL = saturate(dot(m.N, L));
                float NoV = max(dot(m.N, m.V), 1e-4);
                float NoH = saturate(dot(m.N, H));
                float VoH = saturate(dot(m.V, H));

                // 底层：漫反射 + 金属片法线下的 GGX
                vec3 baseBRDF = m.diffuse * ADV_INV_PI + AdvSpecularGGX(m.flakeN, m.V, L, m.aBase, m.f0);

                // 清漆层：F0 = 0.04 的电介质 GGX，用宏观法线（漆面是平的）
                float Fc = AdvF_Schlick(0.04, 1.0, VoH);
                float coatSpec = AdvD_GGX(NoH, m.aCoat) * AdvV_SmithGGX(NoV, NoL, m.aCoat) * Fc;

                // 能量衰减：被清漆反射掉的那部分光不会再到达底层
                float attenuation = mix(1.0, 1.0 - m.coatMask * m.coatFv, _CoatEnergy);
                vec3 brdf = baseBRDF * attenuation + coatSpec * m.coatMask;

                return brdf * PI * light.color * (NoL * light.distanceAttenuation * light.shadowAttenuation);
            }
            //#endregion

            #include "Ch12/LightLoop.glsl"

            //#region flake
            // 程序化金属片：把 UV 切成很小的格子，每格一个随机倾斜的法线
            vec3 Hash33(vec3 p)
            {
                p = fract(p * vec3(0.1031, 0.1030, 0.0973));
                p += dot(p, p.yxz + 33.33);
                return fract((p.xxy + p.yxx) * p.zyx);
            }
            vec3 FlakeNormal(vec2 uv, vec3 T, vec3 B, vec3 N)
            {
                vec2 cell = floor(uv * _FlakeDensity);
                vec3 r = Hash33(vec3(cell, 7.0)) * 2.0 - 1.0;
                return normalize(N + (r.x * T + r.y * B) * _FlakeStrength);
            }
            //#endregion

            //#region frag
            void main()
            {
                vec3 T, B, N; Ch12BuildFrame(T, B, N);
                vec3 V = GetWorldSpaceNormalizeViewDir(positionWS);
                vec2 screenUV = GetNormalizedScreenSpaceUV(gl_FragCoord);
                float NoV = saturate(dot(N, V));

                MaterialCtx m;
                m.N = N; m.V = V;
                m.flakeN = FlakeNormal(uv, T, B, N);
                m.coatMask = _CoatMask;
                m.f0 = mix(vec3(0.04), _BaseColor.rgb, _Metallic);
                m.diffuse = _BaseColor.rgb * (1.0 - _Metallic) * 0.96;

                float prBase = 1.0 - _Smoothness;
                float aBase = max(prBase * prBase, 0.002);
                if (_CoatAffectBase > 0.5)
                {
                    // ① 折射让底层波瓣变宽：α → 等效 Blinn-Phong 指数，乘 (1/1.5)²，再换回来（与 URP 的做法相同）
                    float ieta = mix(1.0, 1.0 / 1.5, m.coatMask);
                    float n = 2.0 / (aBase * aBase) - 2.0;
                    aBase = sqrt(2.0 / (n * ieta * ieta + 2.0));
                    // ② 底层 F0 原本相对空气，现在相对 IOR=1.5 的漆：数值会变小、颜色更饱和
                    vec3 f0Coat = saturate(m.f0 * (m.f0 * 0.526868 + 0.529324) - 0.0482256);
                    m.f0 = mix(m.f0, f0Coat, m.coatMask);
                }
                m.aBase = aBase;
                float prCoat = 1.0 - _CoatSmoothness;
                m.aCoat = max(prCoat * prCoat, 0.002);
                m.coatFv = AdvF_Schlick(0.04, 1.0, NoV);

                vec3 color = AccumulateDirectLighting(m, positionWS, screenUV);

                // 间接光：底层用（修正后的）底层粗糙度，清漆用自己的粗糙度各采一次反射
                float prBaseEff = sqrt(m.aBase);
                vec2 AB = AdvEnvBRDFApprox(prBaseEff, saturate(dot(m.flakeN, V)));
                vec3 baseIndirect = SampleSH(N) * m.diffuse
                    + GlossyEnvironmentReflection(reflect(-V, m.flakeN), positionWS, prBaseEff, 1.0) * (m.f0 * AB.x + AB.y);
                vec2 ABc = AdvEnvBRDFApprox(prCoat, NoV);
                vec3 coatIndirect = GlossyEnvironmentReflection(reflect(-V, N), positionWS, prCoat, 1.0) * (0.04 * ABc.x + ABc.y);

                float attenuation = mix(1.0, 1.0 - m.coatMask * m.coatFv, _CoatEnergy);
                color += baseIndirect * attenuation + coatIndirect * m.coatMask;

                color = MixFog(color, fogFactor);
                fragColor = vec4(color, 1.0);
            }
            //#endregion
            #endif
            ENDGLSL
        }

        UsePass "Cookbook/Common/SHADOWCASTER"
        UsePass "Cookbook/Common/DEPTHONLY"
        UsePass "Cookbook/Common/DEPTHNORMALS"
    }
}
