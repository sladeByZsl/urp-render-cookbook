// 第 19 章：完整的风格化水面。每个特性一个关键字，正文按案例逐个打开。
// 依赖：URP Asset 开启 Depth Texture 与 Opaque Texture；水面放在 Water 层（平面反射相机不渲染它）。
Shader "Cookbook/Ch19/Water"
{
    Properties
    {
        [Header(Depth Color)]
        _ShallowColor ("Shallow Color (A=alpha)", Color) = (0.35,0.85,0.8,0.35)
        _DeepColor ("Deep / Scatter Color (A=alpha)", Color) = (0.03,0.22,0.35,0.95)
        _DepthMax ("Depth For Deep Color (m)", Float) = 2
        _Absorption ("Absorption per meter (RGB)", Vector) = (0.9,0.32,0.22,0)
        _EdgeFade ("Shore Edge Fade (m)", Float) = 0.08

        [Header(Refraction)]
        [Toggle(_REFRACTION)] _Refraction ("Refraction", Float) = 1
        _RefractionStrength ("Refraction Strength", Range(0,0.2)) = 0.05
        [Toggle] _RefractLeakFix ("Fix Foreground Leak", Float) = 1

        [Header(Normals)]
        [Toggle(_NORMALS)] _Normals ("Dual Normals", Float) = 1
        [NoScaleOffset][Normal] _NormalMap ("Normal Map", 2D) = "bump" {}
        _NormalTiling ("Tiling A/B (per meter)", Vector) = (0.18,0.31,0,0)
        _FlowA ("Flow A (xy dir*speed, z strength)", Vector) = (0.03,0.02,0.6,0)
        _FlowB ("Flow B (xy dir*speed, z strength)", Vector) = (-0.025,0.035,0.45,0)

        [Header(Reflection)]
        [Toggle(_REFLECTION)] _Reflection ("Reflection", Float) = 1
        [Toggle(_PLANAR_REFLECTION)] _PlanarReflection ("Use Planar Reflection Texture", Float) = 0
        _ReflectionStrength ("Reflection Strength", Range(0,1)) = 1
        [Toggle] _UseFresnel ("Use Fresnel", Float) = 1
        _Roughness ("Reflection Roughness", Range(0,1)) = 0.05
        _PlanarDistortion ("Planar Reflection Distortion", Range(0,0.2)) = 0.04

        [Header(Specular)]
        [Toggle(_SPECULAR)] _Specular ("Sun Specular", Float) = 1
        _SpecPower ("Spec Power", Range(16,2048)) = 600
        _SpecIntensity ("Spec Intensity", Range(0,4)) = 1

        [Header(Foam)]
        [Toggle(_FOAM)] _Foam ("Shore Foam", Float) = 1
        [NoScaleOffset] _FoamNoise ("Foam Noise", 2D) = "gray" {}
        _FoamColor ("Foam Color", Color) = (0.95,0.98,1,1)
        _FoamDistance ("Foam Distance (m)", Float) = 0.6
        _FoamTiling ("Foam Tiling (per meter)", Float) = 0.35
        _FoamSoftness ("Foam Softness", Range(0.001,0.3)) = 0.03

        [Header(Caustics)]
        [Toggle(_CAUSTICS)] _Caustics ("Caustics", Float) = 1
        _CausticScale ("Caustic Scale (cells per meter)", Float) = 1.6
        _CausticIntensity ("Caustic Intensity", Range(0,4)) = 1.2
        _CausticDepthFade ("Caustic Depth Fade (m)", Float) = 1.5
        _CausticSplit ("Caustic RGB Split", Range(0,0.1)) = 0.025

        [Header(Gerstner Waves)]
        [Toggle(_GERSTNER)] _Gerstner ("Gerstner Waves", Float) = 0
        _WaveA ("Wave A (dir, steepness, wavelength)", Vector) = (1,0.3,0.18,7)
        _WaveB ("Wave B", Vector) = (0.4,1,0.15,4.3)
        _WaveC ("Wave C", Vector) = (-0.7,0.6,0.12,2.6)

        [Header(Time and Debug)]
        [Toggle] _AutoPlay ("Auto Play (_Time)", Float) = 0
        _Phase ("Phase (seconds)", Float) = 0
        [Enum(Off,0,VerticalDepth,1,ViewPath,2,Normal,3,Foam,4,Caustics,5,Fresnel,6)] _DebugView ("Debug View", Float) = 0
    }

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

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma shader_feature_local _REFRACTION
            #pragma shader_feature_local _NORMALS
            #pragma shader_feature_local_fragment _REFLECTION
            #pragma shader_feature_local_fragment _PLANAR_REFLECTION
            #pragma shader_feature_local_fragment _SPECULAR
            #pragma shader_feature_local_fragment _FOAM
            #pragma shader_feature_local_fragment _CAUSTICS
            #pragma shader_feature_local_vertex _GERSTNER
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #pragma multi_compile _ _FORWARD_PLUS
            #pragma multi_compile_fog

            #include "Assets/Cookbook/Ch19/WaterCore.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float4 tangentOS  : TANGENT;
            };

            struct Varyings
            {
                float4 positionCS  : SV_POSITION;
                float3 positionWS  : TEXCOORD0;
                half3  normalWS    : TEXCOORD1;
                half3  tangentWS   : TEXCOORD2;
                half3  bitangentWS : TEXCOORD3;
                half   fogFactor   : TEXCOORD4;
            };

            //#region vert
            Varyings vert(Attributes v)
            {
                Varyings o;
                float3 positionWS = TransformObjectToWorld(v.positionOS.xyz);
                // 平静水面：切线 +X、副切线 +Z、法线 +Y
                float3 tangent = float3(1, 0, 0);
                float3 binormal = float3(0, 0, 1);
            #if defined(_GERSTNER)
                float t = WaterTime();
                float3 p = positionWS;
                positionWS += GerstnerWave(_WaveA, p, t, tangent, binormal);
                positionWS += GerstnerWave(_WaveB, p, t, tangent, binormal);
                positionWS += GerstnerWave(_WaveC, p, t, tangent, binormal);
            #endif
                o.positionWS = positionWS;
                o.positionCS = TransformWorldToHClip(positionWS);
                o.tangentWS = normalize(tangent);
                o.bitangentWS = normalize(binormal);
                o.normalWS = normalize(cross(binormal, tangent));
                o.fogFactor = ComputeFogFactor(o.positionCS.z);
                return o;
            }
            //#endregion

            //#region frag
            half4 frag(Varyings i) : SV_Target
            {
                float t = WaterTime();
                float2 screenUV = GetNormalizedScreenSpaceUV(i.positionCS);
                half3 viewWS = GetWorldSpaceNormalizeViewDir(i.positionWS);
                float surfaceEye = LinearEyeDepth(i.positionWS, UNITY_MATRIX_V);
                Light mainLight = GetMainLight(TransformWorldToShadowCoord(i.positionWS));

                // ---- 法线 ----
                half3 normalTS = half3(0, 0, 1);
            #if defined(_NORMALS)
                normalTS = DualNormalTS(i.positionWS.xz, t);
            #endif
                half3x3 tbn = half3x3(i.tangentWS, i.bitangentWS, i.normalWS);
                half3 normalWS = normalize(mul(normalTS, tbn));

                // ---- 深度 ----
                WaterDepth wd = SampleWaterDepth(screenUV, i.positionWS);
                // 水体自身被照亮的颜色（散射色）：主光 + 环境光
                half3 waterLight = mainLight.color * saturate(mainLight.direction.y) * mainLight.shadowAttenuation + SampleSH(half3(0, 1, 0));
                half3 color;
                half alpha;

            #if defined(_REFRACTION)
                // ---- 折射 + 吸收（不透明合成：自己把“水下画面”算出来，alpha = 1）----
                float2 uvR = RefractUV(screenUV, normalTS, surfaceEye, wd.vertical);
                WaterDepth wdR = SampleWaterDepth(uvR, i.positionWS);
                half3 sceneColor = SampleSceneColor(uvR);
                #if defined(_CAUSTICS)
                sceneColor += Caustics(wdR.sceneWS, wdR.vertical, SceneUpFacing(wd.sceneWS), mainLight, t);
                #endif
                color = UnderwaterColor(sceneColor, wdR.path, _DeepColor.rgb * waterLight);
                // 岸线处和未扰动的画面过渡，避免水面边缘出现一条硬线
                color = lerp(SampleSceneColor(screenUV), color, saturate(wd.vertical / _EdgeFade));
                alpha = 1;
            #else
                // ---- 最简单的版本：按竖直水深在浅色和深色之间插值，靠 alpha 混合透出水底 ----
                half d01 = saturate(wd.vertical / _DepthMax);
                color = lerp(_ShallowColor.rgb, _DeepColor.rgb, d01) * waterLight;
                alpha = lerp(_ShallowColor.a, _DeepColor.a, d01) * saturate(wd.vertical / _EdgeFade);
            #endif

                // ---- 反射 ----
                half fresnel = _UseFresnel > 0.5 ? WaterFresnel(normalWS, viewWS) : 1.0h;
            #if defined(_REFLECTION)
                #if defined(_PLANAR_REFLECTION)
                    half3 reflection = SAMPLE_TEXTURE2D(_PlanarReflectionTex, sampler_PlanarReflectionTex,
                                                        screenUV + normalTS.xy * _PlanarDistortion).rgb;
                #else
                    half3 reflectDir = reflect(-viewWS, normalWS);
                    // Forward+ 下只有带屏幕 UV 的 5 参数版本（反射探针按屏幕分块查找），4 参数版本被 #if 掉了
                    half3 reflection = GlossyEnvironmentReflection(reflectDir, i.positionWS, _Roughness, 1.0h, screenUV);
                #endif
                half kr = fresnel * _ReflectionStrength;
                color = lerp(color, reflection, kr);
                alpha = lerp(alpha, 1.0h, kr);
            #endif

                // ---- 高光 ----
            #if defined(_SPECULAR)
                color += SunSpecular(mainLight, normalWS, viewWS);
            #endif

                // ---- 泡沫 ----
                half foam = 0;
            #if defined(_FOAM)
                foam = ShoreFoam(i.positionWS.xz, wd.vertical, normalTS, t);
                color = lerp(color, _FoamColor.rgb * waterLight, foam);
                alpha = max(alpha, foam);
            #endif

                // ---- 调试视图：把中间量直接画出来 ----
                if (_DebugView > 0.5)
                {
                    half3 dbg = 0;
                    if (_DebugView < 1.5)      dbg = saturate(wd.vertical / _DepthMax);
                    else if (_DebugView < 2.5) dbg = saturate(wd.path / _DepthMax);
                    else if (_DebugView < 3.5) dbg = half3(normalTS.xy * 1.5h + 0.5h, 0.5h);   // 放大切线空间 xy，看清纹理
                    else if (_DebugView < 4.5) dbg = foam;
                    else if (_DebugView < 5.5) dbg = CausticPattern(wd.sceneWS.xz * _CausticScale, t) * 0.5;
                    else                       dbg = fresnel;
                    return half4(dbg, 1);
                }

                color = MixFog(color, i.fogFactor);
                return half4(color, alpha);
            }
            //#endregion
            ENDHLSL
        }
    }
}
