// 第 19 章：完整的风格化水面。每个特性一个关键字，正文按案例逐个打开。（GLSL 版，对应 Ch19/Water.shader）
// 依赖：URP Asset 开启 Depth Texture 与 Opaque Texture；水面放在 Water 层（平面反射相机不渲染它）。
Shader "Cookbook/Ch19/Water"
{
    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent-100" "RenderPipeline"="UniversalPipeline" }

        Pass
        {
            Name "Water"
            Tags { "LightMode"="UniversalForward" }
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            Cull Back

            GLSLPROGRAM
            #pragma shader_feature_local _REFRACTION
            #pragma shader_feature_local _NORMALS
            #pragma shader_feature_local_fragment _REFLECTION
            #pragma shader_feature_local_fragment _PLANAR_REFLECTION
            #pragma shader_feature_local_fragment _SPECULAR
            #pragma shader_feature_local_fragment _FOAM
            #pragma shader_feature_local_fragment _CAUSTICS
            #pragma shader_feature_local_vertex _GERSTNER
            #pragma multi_compile_fog

            #include "Ch19/WaterCore.glsl"

            VARYING vec3  positionWS;
            VARYING vec3  normalWS;
            VARYING vec3  tangentWS;
            VARYING vec3  bitangentWS;
            VARYING float fogFactor;

            #ifdef VERTEX
            //#region vert
            void main()
            {
                vec3 pWS = TransformObjectToWorld(positionOS.xyz);
                // 平静水面：切线 +X、副切线 +Z、法线 +Y
                vec3 tangent = vec3(1, 0, 0);
                vec3 binormal = vec3(0, 0, 1);
            #if defined(_GERSTNER)
                float t = WaterTime();
                vec3 p = pWS;
                pWS += GerstnerWave(_WaveA, p, t, tangent, binormal);
                pWS += GerstnerWave(_WaveB, p, t, tangent, binormal);
                pWS += GerstnerWave(_WaveC, p, t, tangent, binormal);
            #endif
                positionWS = pWS;
                gl_Position = TransformWorldToHClip(pWS);
                tangentWS = normalize(tangent);
                bitangentWS = normalize(binormal);
                normalWS = normalize(cross(binormal, tangent));
                fogFactor = ComputeFogFactor(gl_Position.z);
            }
            //#endregion
            #endif

            #ifdef FRAGMENT
            //#region frag
            void main()
            {
                float t = WaterTime();
                vec2 screenUV = GetNormalizedScreenSpaceUV(gl_FragCoord);
                vec3 viewWS = GetWorldSpaceNormalizeViewDir(positionWS);
                float surfaceEye = LinearEyeDepth(positionWS, UNITY_MATRIX_V);
                Light mainLight = GetMainLight(TransformWorldToShadowCoord(positionWS));

                // ---- 法线 ----
                vec3 normalTS = vec3(0, 0, 1);
            #if defined(_NORMALS)
                normalTS = DualNormalTS(positionWS.xz, t);
            #endif
                // HLSL 的 half3x3(T, B, N) 按行构造、mul(normalTS, tbn)；GLSL 的 mat3(T, B, N) 按列，写成 M * v 结果相同
                mat3 tbn = mat3(tangentWS, bitangentWS, normalWS);
                vec3 N = normalize(tbn * normalTS);

                // ---- 深度 ----
                WaterDepth wd = SampleWaterDepth(screenUV, positionWS);
                // 水体自身被照亮的颜色（散射色）：主光 + 环境光
                vec3 waterLight = mainLight.color * saturate(mainLight.direction.y) * mainLight.shadowAttenuation + SampleSH(vec3(0, 1, 0));
                vec3 color;
                float alpha;

            #if defined(_REFRACTION)
                // ---- 折射 + 吸收（不透明合成：自己把“水下画面”算出来，alpha = 1）----
                vec2 uvR = RefractUV(screenUV, normalTS, surfaceEye, wd.vertical);
                WaterDepth wdR = SampleWaterDepth(uvR, positionWS);
                vec3 sceneColor = SampleSceneColor(uvR);
                #if defined(_CAUSTICS)
                sceneColor += Caustics(wdR.sceneWS, wdR.vertical, SceneUpFacing(wd.sceneWS), mainLight, t);
                #endif
                color = UnderwaterColor(sceneColor, wdR.path, _DeepColor.rgb * waterLight);
                // 岸线处和未扰动的画面过渡，避免水面边缘出现一条硬线
                color = mix(SampleSceneColor(screenUV), color, saturate(wd.vertical / _EdgeFade));
                alpha = 1.0;
            #else
                // ---- 最简单的版本：按竖直水深在浅色和深色之间插值，靠 alpha 混合透出水底 ----
                float d01 = saturate(wd.vertical / _DepthMax);
                color = mix(_ShallowColor.rgb, _DeepColor.rgb, d01) * waterLight;
                alpha = mix(_ShallowColor.a, _DeepColor.a, d01) * saturate(wd.vertical / _EdgeFade);
            #endif

                // ---- 反射 ----
                float fresnel = _UseFresnel > 0.5 ? WaterFresnel(N, viewWS) : 1.0;
            #if defined(_REFLECTION)
                #if defined(_PLANAR_REFLECTION)
                    vec3 reflection = texture(_PlanarReflectionTex, screenUV + normalTS.xy * _PlanarDistortion).rgb;
                #else
                    vec3 reflectDir = reflect(-viewWS, N);
                    // HLSL 版用 Forward+ 的 5 参数版本（带屏幕 UV）；网页版没有反射探针分块，用 4 参数版本
                    vec3 reflection = GlossyEnvironmentReflection(reflectDir, positionWS, _Roughness, 1.0);
                #endif
                float kr = fresnel * _ReflectionStrength;
                color = mix(color, reflection, kr);
                alpha = mix(alpha, 1.0, kr);
            #endif

                // ---- 高光 ----
            #if defined(_SPECULAR)
                color += SunSpecular(mainLight, N, viewWS);
            #endif

                // ---- 泡沫 ----
                float foam = 0.0;
            #if defined(_FOAM)
                foam = ShoreFoam(positionWS.xz, wd.vertical, normalTS, t);
                color = mix(color, _FoamColor.rgb * waterLight, foam);
                alpha = max(alpha, foam);
            #endif

                // ---- 调试视图：把中间量直接画出来 ----
                if (_DebugView > 0.5)
                {
                    vec3 dbg = vec3(0.0);
                    if (_DebugView < 1.5)      dbg = vec3(saturate(wd.vertical / _DepthMax));
                    else if (_DebugView < 2.5) dbg = vec3(saturate(wd.path / _DepthMax));
                    else if (_DebugView < 3.5) dbg = vec3(normalTS.xy * 1.5 + 0.5, 0.5);   // 放大切线空间 xy，看清纹理
                    else if (_DebugView < 4.5) dbg = vec3(foam);
                    else if (_DebugView < 5.5) dbg = vec3(CausticPattern(wd.sceneWS.xz * _CausticScale, t) * 0.5);
                    else                       dbg = vec3(fresnel);
                    fragColor = vec4(dbg, 1.0);
                    return;
                }

                color = MixFog(color, fogFactor);
                fragColor = vec4(color, alpha);
            }
            //#endregion
            #endif
            ENDGLSL
        }
    }
}
