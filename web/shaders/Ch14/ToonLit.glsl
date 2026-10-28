// 本章的完整卡通 Shader：色阶（两层阴影色 / 可选 Ramp 贴图）+ 卡通化接收阴影 + 风格化高光 + 边缘光
// + 附加光 + 平坦环境光 + 背面外扩描边（裁剪空间等宽，可选平滑法线来源）。（GLSL 版，对应 Ch14/ToonLit.shader）
Shader "Cookbook/Ch14/ToonLit"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform vec4 _BaseMap_ST;
        uniform vec4 _BaseColor, _ShadeColor, _ShadeColor2, _SpecColor, _RimColor, _OutlineColor;
        uniform float _Threshold, _Shade2Threshold, _Shade2Strength, _Softness;
        uniform float _ReceiveShadow, _ShadowSoftness, _ShadowNormalOffset;
        uniform float _SpecThreshold, _SpecStrength, _RimWidth, _RimStrength;
        uniform float _AmbientStrength, _AddLightStrength, _OutlineWidth;
        uniform sampler2D _BaseMap;
        uniform sampler2D _RampTex;
        ENDGLSL

        Pass
        {
            Name "ToonForward"
            Tags { "LightMode"="UniversalForwardOnly" }

            GLSLPROGRAM
            #pragma shader_feature_local_fragment _ _RAMPMAP
            #define TOON_VARYINGS
            #include "Ch14/ToonCommon.glsl"

            #ifdef VERTEX
            void main() { ToonVert(); }
            #endif

            #ifdef FRAGMENT
            //#region diffuse
            // 主光的色阶：输入是“半 Lambert × 卡通化后的阴影”，输出是最终的漫反射颜色
            vec3 ToonDiffuse(vec3 albedo, float halfLambert, float shadow)
            {
                // 接收阴影卡通化：把 PCF 的软阴影值也切成硬边，再“乘进”明暗，而不是在最后乘一次
                float toonShadow = mix(1.0, ToonBand(shadow, 0.5, _ShadowSoftness), _ReceiveShadow);
                // 投影区域只压到“第一层阴影”的位置，而不是压到 0（那会掉进第二层阴影，比背光面还暗）
                float shadowedX = min(halfLambert, (_Threshold + _Shade2Threshold) * 0.5);
                float x = mix(shadowedX, halfLambert, toonShadow);
            #if defined(_RAMPMAP)
                return albedo * texture(_RampTex, vec2(clamp(x, 0.01, 0.99), 0.5)).rgb;
            #else
                float band1 = ToonBand(x, _Threshold, _Softness);
                float band2 = ToonBand(x, _Shade2Threshold, _Softness);
                vec3 shade = mix(albedo * _ShadeColor2.rgb, albedo * _ShadeColor.rgb, mix(1.0, band2, _Shade2Strength));
                return mix(shade, albedo, band1);
            #endif
            }
            //#endregion

            //#region addlight
            // 附加光：同样做一次硬边，得到一圈有清晰边界的彩色光斑
            vec3 ToonAdditional(vec3 albedo, vec3 N, Light light)
            {
                float atten = light.distanceAttenuation * light.shadowAttenuation;
                float x = saturate(dot(N, light.direction)) * saturate(atten * 4.0);
                return albedo * light.color * ToonBand(x, 0.3, _Softness + 0.02) * _AddLightStrength;
            }
            //#endregion

            //#region frag
            vec4 frag()
            {
                vec3 N = normalize(normalWS);
                vec3 V = GetWorldSpaceNormalizeViewDir(positionWS);
                vec3 albedo = texture(_BaseMap, TransformTex(uv, _BaseMap_ST)).rgb * _BaseColor.rgb;

                // ---------- 主光 + 阴影 ----------
                // 接收端法线偏移：沿法线挪一点再查阴影图，消除明暗交界处的自阴影锯齿（shadow acne）
                vec4 shadowCoord = TransformWorldToShadowCoord(positionWS + N * _ShadowNormalOffset);
                Light mainLight = GetMainLight(shadowCoord, positionWS, vec4(1.0));
                float NoL = dot(N, mainLight.direction);
                vec3 color = ToonDiffuse(albedo, NoL * 0.5 + 0.5, mainLight.shadowAttenuation) * mainLight.color;

                // 高光与边缘光只出现在“真正被照亮”的区域
                float litMask = ToonBand((NoL * 0.5 + 0.5) * mix(1.0, ToonBand(mainLight.shadowAttenuation, 0.5, _ShadowSoftness), _ReceiveShadow), _Threshold, _Softness);
                vec3 H = normalize(mainLight.direction + V);
                float spec = ToonBand(saturate(dot(N, H)), _SpecThreshold, 0.005) * litMask;
                color += spec * _SpecStrength * _SpecColor.rgb * mainLight.color;
                float rim = FresnelRim(N, V, _RimWidth, 0.02) * litMask;
                color = mix(color, _RimColor.rgb * albedo * mainLight.color * 1.6, rim * _RimStrength);

                // ---------- 附加光 ----------
            #if defined(_ADDITIONAL_LIGHTS)
                // Forward / Forward+ 的光源循环在网页版里都是普通 for 循环
                int lightCount = GetAdditionalLightsCount();
                for (int lightIndex = 0; lightIndex < lightCount; lightIndex++)
                    color += ToonAdditional(albedo, N, GetAdditionalLight(lightIndex, positionWS, vec4(1.0)));
            #endif

                // ---------- 环境光：只取球谐常数项，整块抬亮暗部 ----------
                color += SampleSH(vec3(0.0)) * albedo * _AmbientStrength;

                return vec4(MixFog(color, fogFactor), 1.0);
            }
            //#endregion
            void main() { fragColor = frag(); }
            #endif
            ENDGLSL
        }

        //#region outline
        Pass
        {
            Name "Outline"
            Tags { "LightMode"="SRPDefaultUnlit" }
            Cull Front
            ZWrite On
            GLSLPROGRAM
            #pragma shader_feature_local_vertex _OUTLINENORMAL_MESH _OUTLINENORMAL_TANGENT _OUTLINENORMAL_VERTEXCOLOR
            #include "Ch14/ToonOutlinePass.glsl"
            ENDGLSL
        }
        //#endregion

        // URP 自带的阴影/深度 Pass 与材质无关，网页版用公共的同名 Pass
        UsePass "Cookbook/Common/SHADOWCASTER"
        UsePass "Cookbook/Common/DEPTHONLY"
        UsePass "Cookbook/Common/DEPTHNORMALS"
    }
}
