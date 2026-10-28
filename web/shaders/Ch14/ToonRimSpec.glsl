// 边缘光（三种做法）与风格化高光（三种做法）。漫反射部分沿用上一案例的色阶。（GLSL 版，对应 Ch14/ToonRimSpec.shader）
Shader "Cookbook/Ch14/ToonRimSpec"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform vec4 _BaseColor, _ShadeColor, _RimColor, _SpecColor;
        uniform float _Threshold, _Softness, _RimWidth, _RimWidthPx, _RimDepthThreshold;
        uniform float _SpecThreshold, _SpecSquare;
        uniform vec4 _SpecShiftScale;
        uniform vec4 _SpecSplit;
        ENDGLSL

        Pass
        {
            Name "ToonForward"
            Tags { "LightMode"="UniversalForwardOnly" }

            GLSLPROGRAM
            #pragma shader_feature_local_fragment _RIM_OFF _RIM_FRESNEL _RIM_LIGHTMASKED _RIM_DEPTH
            #pragma shader_feature_local_fragment _SPEC_OFF _SPEC_BLINN _SPEC_TOON _SPEC_STYLIZED
            #define TOON_VARYINGS
            #include "Ch14/ToonCommon.glsl"

            #ifdef VERTEX
            void main() { ToonVert(); }
            #endif

            #ifdef FRAGMENT
            //#region depthrim
            // 屏幕空间深度边缘光：沿法线在屏幕上的投影方向偏移若干像素读深度，
            // 如果那里的深度比自己“深很多”，说明自己处在轮廓边上
            float DepthRim(vec3 N)
            {
                vec3 normalCS = mat3(unity_MatrixVP) * N;     // TransformWorldToHClipDir
                vec2 dirPx = normalize(normalCS.xy * _ScreenParams.xy + 1e-6);
                // WebGL 的像素坐标 y 朝上，与裁剪空间一致，不需要翻转（HLSL 版的 UNITY_UV_STARTS_AT_TOP 分支）
                ivec2 p = ivec2(gl_FragCoord.xy + dirPx * _RimWidthPx);
                p = clamp(p, ivec2(0), ivec2(_ScreenParams.xy) - 1);
                float sceneDepth = LinearEyeDepth(texelFetch(_CameraDepthTexture, p, 0).r, _ZBufferParams);   // LoadSceneDepth
                float selfDepth = LinearEyeDepth(gl_FragCoord.z, _ZBufferParams);
                return step(_RimDepthThreshold, sceneDepth - selfDepth);
            }
            //#endregion

            //#region frag
            vec4 frag()
            {
                vec3 N = normalize(normalWS);
                vec3 T = normalize(tangentWS.xyz);
                vec3 B = cross(N, T) * tangentWS.w;
                vec3 V = GetWorldSpaceNormalizeViewDir(positionWS);
                Light light = GetMainLight();
                vec3 L = light.direction;
                float NoL = dot(N, L);
                float band = ToonBand(NoL * 0.5 + 0.5, _Threshold, _Softness);
                vec3 color = mix(_ShadeColor.rgb, _BaseColor.rgb, band) * light.color;
                color += SampleSH(vec3(0.0)) * _BaseColor.rgb * 0.3;

                // ---------- 高光 ----------
                vec3 H = normalize(L + V);
                float spec = 0.0;
            #if defined(_SPEC_BLINN)
                spec = pow(saturate(dot(N, H)), 64.0);                                // 对照：普通 Blinn-Phong
            #elif defined(_SPEC_TOON)
                spec = ToonBand(saturate(dot(N, H)), _SpecThreshold, 0.005);          // 色阶化：一个硬边色块
            #elif defined(_SPEC_STYLIZED)
                spec = StylizedSpecular(N, T, B, H, _SpecShiftScale, _SpecSplit.xy, _SpecSquare, _SpecThreshold, 0.005);
            #endif
                color += spec * band * _SpecColor.rgb * light.color;                  // 只在亮部出现

                // ---------- 边缘光 ----------
                float rim = 0.0;
            #if defined(_RIM_FRESNEL)
                rim = FresnelRim(N, V, _RimWidth, 0.02);
            #elif defined(_RIM_LIGHTMASKED)
                // 只保留朝光一侧的边缘：边缘光“像是被主光勾出来的”，背光侧不会到处发亮
                rim = FresnelRim(N, V, _RimWidth, 0.02) * ToonBand(NoL, 0.0, 0.1);
            #elif defined(_RIM_DEPTH)
                rim = DepthRim(N) * ToonBand(NoL, -0.2, 0.1);
            #endif
                color = mix(color, _RimColor.rgb * light.color, rim);

                color = MixFog(color, fogFactor);
                return vec4(color, 1.0);
            }
            //#endregion
            void main() { fragColor = frag(); }
            #endif
            ENDGLSL
        }

        UsePass "Cookbook/Common/SHADOWCASTER"
        UsePass "Cookbook/Common/DEPTHONLY"
        UsePass "Cookbook/Common/DEPTHNORMALS"
    }
}
