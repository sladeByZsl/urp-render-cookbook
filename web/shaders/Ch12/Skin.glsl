// 皮肤：三种次表面散射近似的漫反射 + 双瓣 GGX 高光。
//   LAMBERT —— 对照组；WRAP —— 按通道不同包裹量的 Wrap Lighting；LUT —— 预积分皮肤散射（Penner 2011）
// （GLSL 版，对应 Ch12/Skin.shader）
Shader "Cookbook/Ch12/Skin"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform vec4  _BaseColor, _ScatterColor;
        uniform float _Wrap, _CurvatureScale, _Curvature, _Smoothness, _SpecularF0;
        uniform sampler2D _SkinLUT;
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }

            GLSLPROGRAM
            #pragma shader_feature_local_fragment _DIFFUSE_LAMBERT _DIFFUSE_WRAP _DIFFUSE_LUT

            #include "Ch12/Ch12Common.glsl"

            #ifdef VERTEX
            void main() { Ch12Vert(); }
            #endif

            #ifdef FRAGMENT
            struct MaterialCtx
            {
                vec3 N, V;
                vec3 albedo;
                float curvature;   // 0~1，查 LUT 的 v 坐标
                float a;
            };

            //#region diffuse
            vec3 SkinDiffuse(MaterialCtx m, float NoLu, float shadow)
            {
            #if defined(_DIFFUSE_WRAP)
                // 每个通道包裹量不同：红光在皮下走得最远，所以红通道包得最多
                // 阴影同样折进 N·L：阴影里的点按“刚好背光”处理，包裹项让阴影边缘也透出一点红
                vec3 w = _Wrap * _ScatterColor.rgb;
                float ndl = mix(min(NoLu, 0.0), NoLu, shadow);
                return saturate((ndl + w) / (1.0 + w));
            #elif defined(_DIFFUSE_LUT)
                // 预积分 LUT：u = N·L 映射到 0~1，v = 曲率
                // 阴影先折进 N·L 再查表，让阴影边缘也带上散射的红色过渡
                float u = mix(min(NoLu, 0.0), NoLu, shadow) * 0.5 + 0.5;
                return textureLod(_SkinLUT, vec2(u, m.curvature), 0.0).rgb;
            #else
                return vec3(saturate(NoLu) * shadow);
            #endif
            }
            //#endregion

            //#region shade
            vec3 ShadeOneLight(MaterialCtx m, Light light)
            {
                vec3 L = light.direction;
                float NoLu = dot(m.N, L);
                float NoL = saturate(NoLu);
                vec3 diffuse = m.albedo * SkinDiffuse(m, NoLu, light.shadowAttenuation);

                // 双瓣高光：一个偏光滑、一个偏粗糙，各占一半，模拟皮脂层 + 角质层
                vec3 spec = 0.5 * AdvSpecularGGX(m.N, m.V, L, m.a, _SpecularF0)
                          + 0.5 * AdvSpecularGGX(m.N, m.V, L, saturate(m.a * 2.2), _SpecularF0);
                spec *= PI * NoL * light.shadowAttenuation;

                return (diffuse + spec) * light.color * light.distanceAttenuation;
            }
            //#endregion

            #include "Ch12/LightLoop.glsl"

            void main()
            {
                vec3 T, B, N; Ch12BuildFrame(T, B, N);
                vec3 V = GetWorldSpaceNormalizeViewDir(positionWS);
                vec2 screenUV = GetNormalizedScreenSpaceUV(gl_FragCoord);

                //#region curvature
                // 曲率 = 法线变化量 / 位置变化量，用屏幕空间导数估计（单位 1/米）
                float curv = length(fwidth(N)) / max(length(fwidth(positionWS)), 1e-5);
                curv = saturate(curv * _CurvatureScale);   // 换算到 LUT 的 0~1，比例取决于场景单位和 LUT 的定义
                if (_Curvature >= 0.0) curv = _Curvature;
                //#endregion

                MaterialCtx m;
                m.N = N; m.V = V;
                m.albedo = _BaseColor.rgb;
                m.curvature = curv;
                float pr = 1.0 - _Smoothness;
                m.a = max(pr * pr, 0.002);

                vec3 color = AccumulateDirectLighting(m, positionWS, screenUV);

                float NoV = saturate(dot(N, V));
                vec2 AB = AdvEnvBRDFApprox(pr, NoV);
                color += SampleSH(N) * m.albedo;
                color += GlossyEnvironmentReflection(reflect(-V, N), positionWS, pr, 1.0) * (_SpecularF0 * AB.x + AB.y);

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
