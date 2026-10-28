// 各向异性 GGX：拉丝金属。切线方向 T = 拉丝（划痕）方向。
// （GLSL 版，对应 Ch12/Anisotropic.shader）
Shader "Cookbook/Ch12/Anisotropic"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform vec4  _BrushTex_ST;
        uniform vec4  _BaseColor;
        uniform float _Metallic, _Smoothness, _Anisotropy, _BrushStrength, _AnisoIBL;
        uniform sampler2D _BrushTex;
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }

            GLSLPROGRAM
            #pragma shader_feature_local_fragment _DIR_TANGENT _DIR_BITANGENT _DIR_RADIAL

            #include "Ch12/Ch12Common.glsl"

            #ifdef VERTEX
            void main() { Ch12Vert(); }
            #endif

            #ifdef FRAGMENT
            struct MaterialCtx
            {
                vec3 N, V, T, B;
                vec3 diffuse, f0;
                float at, ab;
            };

            //#region shade
            vec3 ShadeOneLight(MaterialCtx m, Light light)
            {
                vec3 L = light.direction;
                vec3 H = normalize(m.V + L);
                float NoL = saturate(dot(m.N, L));
                float NoV = max(dot(m.N, m.V), 1e-4);
                float NoH = saturate(dot(m.N, H));
                float VoH = saturate(dot(m.V, H));

                float D = AdvD_GGXAniso(dot(m.T, H), dot(m.B, H), NoH, m.at, m.ab);
                float Vis = AdvV_SmithGGXAniso(dot(m.T, m.V), dot(m.B, m.V), NoV,
                                               dot(m.T, L), dot(m.B, L), NoL, m.at, m.ab);
                vec3 F = AdvF_Schlick(m.f0, 1.0, VoH);

                vec3 brdf = m.diffuse * ADV_INV_PI + D * Vis * F;
                return brdf * PI * light.color * (NoL * light.distanceAttenuation * light.shadowAttenuation);
            }
            //#endregion

            #include "Ch12/LightLoop.glsl"

            void main()
            {
                vec3 T, B, N; Ch12BuildFrame(T, B, N);
                vec3 V = GetWorldSpaceNormalizeViewDir(positionWS);
                vec2 screenUV = GetNormalizedScreenSpaceUV(gl_FragCoord);

                //#region dir
                // 选择拉丝方向；条纹贴图的纹路沿 U 方向，采样坐标也跟着转
                vec2 streakUV = uv;
            #if defined(_DIR_BITANGENT)
                vec3 tmp = T; T = B; B = -tmp;
                streakUV = uv.yx;
            #elif defined(_DIR_RADIAL)
                // 以 UV 中心为圆心的同心圆拉丝（锅底、CD 纹）：切线 = 圆周方向
                vec2 d = uv - 0.5;
                vec2 c = normalize(vec2(-d.y, d.x) + 1e-5);
                T = normalize(c.x * T + c.y * B);
                B = cross(N, T);
                streakUV = vec2(0.5, length(d) * 2.0);   // 条纹只随半径变化 → 同心圆
            #endif
                //#endregion

                // 拉丝条纹：一点点调制粗糙度和颜色，让表面“有料”
                float streak = texture(_BrushTex, streakUV * _BrushTex_ST.xy + _BrushTex_ST.zw).r;
                float pr = saturate(1.0 - _Smoothness + (streak - 0.5) * _BrushStrength * 0.6);
                float a = max(pr * pr, 0.002);
                vec3 albedo = _BaseColor.rgb * mix(1.0, 0.75 + 0.5 * streak, _BrushStrength);

                MaterialCtx m;
                m.N = N; m.V = V; m.T = T; m.B = B;
                m.f0 = mix(vec3(0.04), albedo, _Metallic);
                m.diffuse = albedo * (1.0 - _Metallic) * 0.96;
                AdvAnisoRoughness(a, _Anisotropy, m.at, m.ab);

                vec3 color = AccumulateDirectLighting(m, positionWS, screenUV);

                //#region bent
                // 各向异性的环境反射：没法预滤波，常用“弯曲法线”近似（Filament 的做法）
                // grooveDir 是光滑的方向（划痕走向）；anisoN = V 投影到垂直于它的平面上，
                // 把法线朝 anisoN 扭一扭，反射就会沿“粗糙方向”被拉长
                vec3 grooveDir = _Anisotropy >= 0.0 ? T : B;
                vec3 anisoT = cross(grooveDir, V);
                vec3 anisoN = cross(anisoT, grooveDir);
                float bend = abs(_Anisotropy) * saturate(5.0 * pr) * _AnisoIBL;
                vec3 bentN = normalize(mix(N, anisoN, bend));
                vec3 R = reflect(-V, bentN);
                //#endregion

                vec2 AB = AdvEnvBRDFApprox(pr, saturate(dot(N, V)));
                color += SampleSH(N) * m.diffuse;
                color += GlossyEnvironmentReflection(R, positionWS, pr, 1.0) * (m.f0 * AB.x + AB.y);

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
