// 薄膜干涉（Iridescence）：肥皂泡、油膜、甲虫壳、回火金属的彩虹色。
// 菲涅尔项 F 被替换成“三层结构的干涉反射率”，其余仍是 GGX。
// （GLSL 版，对应 Ch12/ThinFilm.shader）
Shader "Cookbook/Ch12/ThinFilm"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform vec4  _ThicknessTex_ST;
        uniform vec4  _BaseColor;
        uniform float _BaseF0, _Thickness, _ThicknessVar, _FilmIOR, _Smoothness;
        uniform sampler2D _ThicknessTex;
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }

            GLSLPROGRAM
            #pragma shader_feature_local_fragment _FILM_SPECTRAL _FILM_RGB3 _FILM_BELCOUR

            #include "Ch12/Ch12Common.glsl"

            #ifdef VERTEX
            void main() { Ch12Vert(); }
            #endif

            #ifdef FRAGMENT
            float Sq(float x) { return x * x; }

            #if defined(_FILM_BELCOUR)
            // ---- 以下移植自 core 包 BSDF.hlsl 的 EvalSensitivity / EvalIridescence（HDRP 用的 Belcour & Barla 2017 实现）----
            // HLSL 版直接调用 core 包里的函数，GLSL 版没有这个库，所以把它们原样抄在这里
            float IorToFresnel0(float transmittedIor, float incidentIor) { return Sq((transmittedIor - incidentIor) / (transmittedIor + incidentIor)); }
            float F_Schlick(float f0, float u) { float x = 1.0 - u; float x2 = x * x; return (1.0 - f0) * (x * x2 * x2) + f0; }
            vec3 F_Schlick(vec3 f0, float u) { float x = 1.0 - u; float x2 = x * x; return (1.0 - f0) * (x * x2 * x2) + f0; }

            // 在傅里叶空间里求 XYZ 敏感度曲线（高斯拟合），再转到线性 sRGB
            vec3 EvalSensitivity(float opd, float shift)
            {
                float phase = 2.0 * PI * opd * 1e-6;
                vec3 val = vec3(5.4856e-13, 4.4201e-13, 5.2481e-13);
                vec3 pos = vec3(1.6810e+06, 1.7953e+06, 2.2084e+06);
                vec3 var = vec3(4.3278e+09, 9.3046e+09, 6.6121e+09);
                vec3 xyz = val * sqrt(2.0 * PI * var) * cos(pos * phase + shift) * exp(-var * phase * phase);
                xyz.x += 9.7470e-14 * sqrt(2.0 * PI * 4.5282e+09) * cos(2.2399e+06 * phase + shift) * exp(-4.5282e+09 * phase * phase);
                xyz /= 1.0685e-7;
                // XYZ_2_REC709_MAT（HLSL 按行初始化；GLSL 写成 v * mat3(行0, 行1, 行2)）
                return xyz * mat3( 3.2409699419, -1.5373831776, -0.4986107603,
                                  -0.9692436363,  1.8759675015,  0.0415550574,
                                   0.0556300797, -0.2039769589,  1.0569715142);
            }

            // 电介质基底上一层薄膜的反射率
            vec3 EvalIridescence(float eta_1, float cosTheta1, float iridescenceThickness, vec3 baseLayerFresnel0)
            {
                vec3 I;
                // 厚度单位是微米，0.5 对应 500nm
                float Dinc = 3.0 * iridescenceThickness;
                // 用厚度反推薄膜折射率（HDRP 的“单参数”做法）
                float eta_2 = mix(2.0, 1.0, iridescenceThickness);
                float sinTheta2Sq = Sq(eta_1 / eta_2) * (1.0 - Sq(cosTheta1));
                float cosTheta2Sq = (1.0 - sinTheta2Sq);
                if (cosTheta2Sq < 0.0)
                    I = vec3(1.0);   // 全反射
                else
                {
                    float cosTheta2 = sqrt(cosTheta2Sq);

                    // 第一个界面
                    float R0 = IorToFresnel0(eta_2, eta_1);
                    float R12 = F_Schlick(R0, cosTheta1);
                    float T121 = 1.0 - R12;
                    float phi12 = 0.0;
                    float phi21 = PI - phi12;

                    // 第二个界面
                    vec3 R23 = F_Schlick(baseLayerFresnel0, cosTheta2);
                    float phi23 = 0.0;

                    // 相位差
                    float OPD = Dinc * cosTheta2;
                    float phi = phi21 + phi23;

                    vec3 R123 = clamp(R12 * R23, 1e-5, 0.9999);
                    vec3 r123 = sqrt(R123);
                    vec3 Rs = Sq(T121) * R23 / (vec3(1.0) - R123);

                    // m = 0 项
                    vec3 C0 = R12 + Rs;
                    I = C0;

                    // m > 0 项
                    vec3 Cm = Rs - T121;
                    for (int m = 1; m <= 2; ++m)
                    {
                        Cm *= r123;
                        vec3 Sm = 2.0 * EvalSensitivity(float(m) * OPD, float(m) * phi);
                        I += Cm * Sm;
                    }
                    // 超出色域的颜色可能为负，截到 0
                    I = max(I, vec3(0.0));
                }
                return I;
            }
            #endif

            //#region film
            vec3 FilmFresnel(float cosTheta, float thickness)
            {
            #if defined(_FILM_RGB3)
                // 偷懒版：只在 R/G/B 三个代表波长上算一次 Airy 反射率
                float sin2 = (1.0 - cosTheta * cosTheta) / (_FilmIOR * _FilmIOR);
                float opd = 2.0 * _FilmIOR * thickness * sqrt(saturate(1.0 - sin2));
                float r12 = -sqrt(AdvF_Schlick(Sq((1.0 - _FilmIOR) / (1.0 + _FilmIOR)), 1.0, cosTheta));
                float baseIOR = (1.0 + sqrt(_BaseF0)) / (1.0 - sqrt(min(_BaseF0, 0.99)));
                float r23 = sign(_FilmIOR - baseIOR) * sqrt(Sq((_FilmIOR - baseIOR) / (_FilmIOR + baseIOR)));
                return vec3(AdvAiryReflectance(r12, r23, opd, 650.0),
                            AdvAiryReflectance(r12, r23, opd, 532.0),
                            AdvAiryReflectance(r12, r23, opd, 450.0));
            #elif defined(_FILM_BELCOUR)
                // core 包里 HDRP 用的 Belcour & Barla 2017 实现；它的厚度参数是 0~1 的归一化值
                return EvalIridescence(1.0, cosTheta, saturate(thickness / 1000.0), vec3(_BaseF0));
            #else
                return AdvThinFilm(cosTheta, thickness, _FilmIOR, _BaseF0);
            #endif
            }
            //#endregion

            struct MaterialCtx
            {
                vec3 N, V;
                vec3 diffuse;
                float a, thickness;
            };

            vec3 ShadeOneLight(MaterialCtx m, Light light)
            {
                vec3 L = light.direction;
                vec3 H = normalize(m.V + L);
                float NoL = saturate(dot(m.N, L));
                float NoV = max(dot(m.N, m.V), 1e-4);
                float NoH = saturate(dot(m.N, H));
                float VoH = saturate(dot(m.V, H));
                vec3 F = FilmFresnel(VoH, m.thickness);   // 用薄膜反射率替换 Schlick
                vec3 spec = AdvD_GGX(NoH, m.a) * AdvV_SmithGGX(NoV, NoL, m.a) * F;
                vec3 brdf = m.diffuse * ADV_INV_PI + spec;
                return brdf * PI * light.color * (NoL * light.distanceAttenuation * light.shadowAttenuation);
            }

            #include "Ch12/LightLoop.glsl"

            void main()
            {
                vec3 T, B, N; Ch12BuildFrame(T, B, N);
                vec3 V = GetWorldSpaceNormalizeViewDir(positionWS);
                vec2 screenUV = GetNormalizedScreenSpaceUV(gl_FragCoord);
                float NoV = saturate(dot(N, V));

                float tn = texture(_ThicknessTex, TransformTex(uv, _ThicknessTex_ST)).r;

                MaterialCtx m;
                m.N = N; m.V = V;
                m.diffuse = _BaseColor.rgb;
                m.thickness = max(_Thickness + (tn - 0.5) * 2.0 * _ThicknessVar, 0.0);
                float pr = 1.0 - _Smoothness;
                m.a = max(pr * pr, 0.002);

                vec3 color = AccumulateDirectLighting(m, positionWS, screenUV);

                // 环境反射同样用薄膜反射率，角度取 N·V；AB.x + AB.y 近似粗糙度带来的能量损失
                vec2 AB = AdvEnvBRDFApprox(pr, NoV);
                color += SampleSH(N) * m.diffuse;
                color += GlossyEnvironmentReflection(reflect(-V, N), positionWS, pr, 1.0)
                       * FilmFresnel(NoV, m.thickness) * (AB.x + AB.y);

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
