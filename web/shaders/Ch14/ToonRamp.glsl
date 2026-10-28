// 色阶化漫反射：Lambert → step → smoothstep → Ramp 贴图，以及阴影色的几种给法。（GLSL 版，对应 Ch14/ToonRamp.shader）
Shader "Cookbook/Ch14/ToonRamp"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform vec4 _BaseColor, _ShadeColor, _ShadeColor2;
        uniform float _Threshold, _Softness, _Shade2Threshold, _Shade2Strength, _AmbientStrength;
        uniform sampler2D _RampTex;
        ENDGLSL

        Pass
        {
            Name "ToonForward"
            Tags { "LightMode"="UniversalForwardOnly" }

            GLSLPROGRAM
            #pragma shader_feature_local_fragment _RAMP_LAMBERT _RAMP_STEP _RAMP_SMOOTH _RAMP_TEXTURE
            #define TOON_VARYINGS
            #include "Ch14/ToonCommon.glsl"

            #ifdef VERTEX
            void main() { ToonVert(); }
            #endif

            #ifdef FRAGMENT
            //#region frag
            vec4 frag()
            {
                vec3 N = normalize(normalWS);
                Light light = GetMainLight();
                float NoL = dot(N, light.direction);
                float halfLambert = NoL * 0.5 + 0.5;     // 0~1，比 saturate(NoL) 更适合当查表坐标

                vec3 color;
            #if defined(_RAMP_LAMBERT)
                color = _BaseColor.rgb * saturate(NoL);                      // 对照：普通 Lambert
            #elif defined(_RAMP_TEXTURE)
                // Ramp 贴图：横向就是“明暗 → 颜色”的映射表，美术可以随意画色阶与色相
                vec3 ramp = texture(_RampTex, vec2(clamp(halfLambert, 0.01, 0.99), 0.5)).rgb;
                color = _BaseColor.rgb * ramp;
            #else
              #if defined(_RAMP_STEP)
                float band = step(_Threshold, halfLambert);                  // 硬边：会有锯齿
              #else
                // 软一点的硬边：过渡宽度至少一个像素（fwidth = 这个量在相邻像素间的变化），硬边也不会出锯齿
                float band = ToonBand(halfLambert, _Threshold, max(_Softness, fwidth(halfLambert)));
              #endif
                // 亮部用固有色，暗部用美术指定的阴影色，而不是“固有色 × 0.5”
                color = mix(_ShadeColor.rgb, _BaseColor.rgb, band);
                // 可选的第二层阴影：在更暗的位置再切一档
                float band2 = ToonBand(halfLambert, _Shade2Threshold, _Softness);
                color = mix(mix(color, _ShadeColor2.rgb, _Shade2Strength), color, band2);
            #endif
                color *= light.color;

                // 环境光：只取球谐的常数项（平均环境色），避免环境光把色块又“抹圆”
                color += SampleSH(vec3(0.0)) * _BaseColor.rgb * _AmbientStrength;
                color = MixFog(color, fogFactor);
                return vec4(color, 1.0);
            }
            //#endregion
            void main() { fragColor = frag(); }
            #endif
            ENDGLSL
        }

        // URP 自带的阴影/深度 Pass 与材质无关，网页版用公共的同名 Pass
        UsePass "Cookbook/Common/SHADOWCASTER"
        UsePass "Cookbook/Common/DEPTHONLY"
        UsePass "Cookbook/Common/DEPTHNORMALS"
    }
}
