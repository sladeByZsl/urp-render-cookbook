// URP 内置后处理的 GLSL 版本：Bloom（Bloom.shader）、颜色分级 LUT（LutBuilderHdr/Ldr.shader）与 Uber（UberPost.shader）。
// Uber 里包含：镜头畸变、色差、Bloom（含镜头脏污）、暗角、颜色分级（查 LUT）、胶片颗粒——和 URP 一样一次完成。
Shader "Hidden/Cookbook/PostFX"
{
    SubShader
    {
        ZTest Always ZWrite Off Cull Off
        GLSLINCLUDE
        VARYING vec2 uv;
        #ifdef VERTEX
        void main()
        {
            // 全屏三角形：gl_VertexID 0,1,2 → 覆盖整个屏幕
            vec2 p = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);
            uv = p;
            gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
        }
        #endif
        uniform vec4 _Params;     // (scatter, clamp, threshold, thresholdKnee)
        uniform float _HighQuality;
        uniform sampler2D _SourceTexLowMip;
        uniform vec4 _SourceTexLowMip_TexelSize;
        float Max3(vec3 c) { return max(c.r, max(c.g, c.b)); }

        #include "URP/PostFXCommon.glsl"
        ENDGLSL

        Pass
        {
            Name "BloomPrefilter"
            GLSLPROGRAM
            #ifdef FRAGMENT
            void main()
            {
                vec3 color;
                if (_HighQuality > 0.5)
                {
                    // 13 tap（URP 的 _BLOOM_HQ；注意 URP 两个方向都用 texelSize.x）
                    float t = _BlitTexture_TexelSize.x;
                    vec3 A = texture(_BlitTexture, uv + t * vec2(-1.0, -1.0)).rgb;
                    vec3 B = texture(_BlitTexture, uv + t * vec2( 0.0, -1.0)).rgb;
                    vec3 C = texture(_BlitTexture, uv + t * vec2( 1.0, -1.0)).rgb;
                    vec3 D = texture(_BlitTexture, uv + t * vec2(-0.5, -0.5)).rgb;
                    vec3 E = texture(_BlitTexture, uv + t * vec2( 0.5, -0.5)).rgb;
                    vec3 F = texture(_BlitTexture, uv + t * vec2(-1.0,  0.0)).rgb;
                    vec3 G = texture(_BlitTexture, uv).rgb;
                    vec3 H = texture(_BlitTexture, uv + t * vec2( 1.0,  0.0)).rgb;
                    vec3 I = texture(_BlitTexture, uv + t * vec2(-0.5,  0.5)).rgb;
                    vec3 J = texture(_BlitTexture, uv + t * vec2( 0.5,  0.5)).rgb;
                    vec3 K = texture(_BlitTexture, uv + t * vec2(-1.0,  1.0)).rgb;
                    vec3 L = texture(_BlitTexture, uv + t * vec2( 0.0,  1.0)).rgb;
                    vec3 M = texture(_BlitTexture, uv + t * vec2( 1.0,  1.0)).rgb;
                    vec2 div = (1.0 / 4.0) * vec2(0.5, 0.125);
                    color = (D + E + I + J) * div.x;
                    color += (A + B + G + F) * div.y;
                    color += (B + C + H + G) * div.y;
                    color += (F + G + L + K) * div.y;
                    color += (G + H + M + L) * div.y;
                }
                else
                    color = texture(_BlitTexture, uv).rgb;
                // 用户可调的上限，防止极亮的高光
                color = min(vec3(_Params.y), color);
                // 阈值（软膝）
                float threshold = _Params.z, knee = _Params.w;
                float brightness = Max3(color);
                float softness = clamp(brightness - threshold + knee, 0.0, 2.0 * knee);
                softness = (softness * softness) / (4.0 * knee + 1e-4);
                float multiplier = max(brightness - threshold, softness) / max(brightness, 1e-4);
                fragColor = vec4(max(color * multiplier, 0.0), 1.0);
            }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "BloomBlurH"
            GLSLPROGRAM
            #ifdef FRAGMENT
            void main()
            {
                // 读上一级（两倍大小），9 tap 高斯，同时完成降采样
                float t = _BlitTexture_TexelSize.x * 2.0;
                vec3 c = vec3(0.0);
                c += texture(_BlitTexture, uv - vec2(t * 4.0, 0)).rgb * 0.01621622;
                c += texture(_BlitTexture, uv - vec2(t * 3.0, 0)).rgb * 0.05405405;
                c += texture(_BlitTexture, uv - vec2(t * 2.0, 0)).rgb * 0.12162162;
                c += texture(_BlitTexture, uv - vec2(t * 1.0, 0)).rgb * 0.19459459;
                c += texture(_BlitTexture, uv).rgb * 0.22702703;
                c += texture(_BlitTexture, uv + vec2(t * 1.0, 0)).rgb * 0.19459459;
                c += texture(_BlitTexture, uv + vec2(t * 2.0, 0)).rgb * 0.12162162;
                c += texture(_BlitTexture, uv + vec2(t * 3.0, 0)).rgb * 0.05405405;
                c += texture(_BlitTexture, uv + vec2(t * 4.0, 0)).rgb * 0.01621622;
                fragColor = vec4(c, 1.0);
            }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "BloomBlurV"
            GLSLPROGRAM
            #ifdef FRAGMENT
            void main()
            {
                // 利用双线性插值，5 次采样等于 9 tap
                float t = _BlitTexture_TexelSize.y;
                vec3 c = texture(_BlitTexture, uv - vec2(0, t * 3.23076923)).rgb * 0.07027027
                       + texture(_BlitTexture, uv - vec2(0, t * 1.38461538)).rgb * 0.31621622
                       + texture(_BlitTexture, uv).rgb * 0.22702703
                       + texture(_BlitTexture, uv + vec2(0, t * 1.38461538)).rgb * 0.31621622
                       + texture(_BlitTexture, uv + vec2(0, t * 3.23076923)).rgb * 0.07027027;
                fragColor = vec4(c, 1.0);
            }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "BloomUpsample"
            GLSLPROGRAM
            #ifdef FRAGMENT
            void main()
            {
                vec3 highMip = texture(_BlitTexture, uv).rgb;
                vec3 lowMip = _HighQuality > 0.5
                    ? SampleTexture2DBicubic(_SourceTexLowMip, uv, _SourceTexLowMip_TexelSize.zwxy, vec2(1.0)).rgb
                    : texture(_SourceTexLowMip, uv).rgb;
                fragColor = vec4(mix(highMip, lowMip, _Params.x), 1.0);
            }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "LutBuilderHdr"
            GLSLPROGRAM
            #include "URP/ColorGrading.glsl"
            uniform vec4 _LutBuild_Params;   // URP 的 _Lut_Params：(lut_height, 0.5/lut_width, 0.5/lut_height, lut_height/(lut_height-1))
            #ifdef FRAGMENT
            void main()
            {
                vec3 colorLutSpace = GetLutStripValue(uv, _LutBuild_Params);
                vec3 graded = TonemapHdr(ColorGradeHdr(colorLutSpace));
                fragColor = vec4(graded, 1.0);
            }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "LutBuilderLdr"
            GLSLPROGRAM
            #include "URP/ColorGrading.glsl"
            uniform vec4 _LutBuild_Params;
            #ifdef FRAGMENT
            void main()
            {
                vec3 colorLinear = GetLutStripValue(uv, _LutBuild_Params);
                fragColor = vec4(ColorGradeLdr(colorLinear), 1.0);
            }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "Uber"
            GLSLPROGRAM
            #include "URP/ColorGrading.glsl"
            uniform sampler2D _Bloom_Texture;
            uniform vec4 _Bloom_TexSize;     // (宽, 高, 1/宽, 1/高)
            uniform vec4 _BloomParams;       // (强度, 色调 rgb)
            uniform float _BloomEnabled;     // 0 关，1 LQ，2 HQ（双三次采样 Bloom 贴图）
            uniform sampler2D _LensDirt_Texture;
            uniform vec4 _LensDirt_Params;   // (缩放 xy, 偏移 zw)：按 cover 方式铺满屏幕
            uniform float _LensDirt_Intensity;
            uniform vec4 _Distortion_Params1;  // (中心 xy, 轴向倍数 zw)
            uniform vec4 _Distortion_Params2;  // (theta, sigma, 1/scale, 强度×100)
            uniform float _DistortionEnabled;
            uniform float _Chroma_Params;      // 色差强度 × 0.05；0 = 关
            uniform vec4 _Vignette1;           // (颜色 rgb, 圆形?宽高比:1)
            uniform vec4 _Vignette2;           // (中心 xy, 强度×3, 平滑×5)
            uniform sampler2D _Grain_Texture;
            uniform vec2 _Grain_Params;        // (强度×4, 响应)
            uniform vec4 _Grain_TilingParams;  // (屏幕/贴图 xy, 随机偏移 zw)
            uniform float _GrainEnabled;

            vec2 DistortUV(vec2 uv)
            {
                if (_DistortionEnabled < 0.5) return uv;
                vec2 DistCenter = _Distortion_Params1.xy, DistAxis = _Distortion_Params1.zw;
                float DistTheta = _Distortion_Params2.x, DistSigma = _Distortion_Params2.y, DistScale = _Distortion_Params2.z, DistIntensity = _Distortion_Params2.w;
                uv = (uv - 0.5) * DistScale + 0.5;
                vec2 ruv = DistAxis * (uv - 0.5 - DistCenter);
                float ru = length(ruv);
                if (DistIntensity > 0.0)
                {
                    float wu = ru * DistTheta;
                    ru = tan(wu) * (1.0 / (ru * DistSigma));
                    uv = uv + ruv * (ru - 1.0);
                }
                else
                {
                    ru = (1.0 / ru) * DistTheta * atan(ru * DistSigma);
                    uv = uv + ruv * (ru - 1.0);
                }
                return uv;
            }

            vec3 ApplyVignette(vec3 inputColor, vec2 uv, vec2 center, float intensity, float roundness, float smoothness, vec3 color)
            {
                vec2 dist = abs(uv - center) * intensity;
                dist.x *= roundness;
                float vfactor = pow(saturate(1.0 - dot(dist, dist)), smoothness);
                return inputColor * mix(color, vec3(1.0), vfactor);
            }

            vec3 ApplyGrain(vec3 inputColor, vec2 uv)
            {
                // 颗粒贴图 [0,1]，0.5 为中性（URP 用 alpha 通道；这些贴图的 alpha 来自灰度，等于 r）
                float grain = texture(_Grain_Texture, uv * _Grain_TilingParams.xy + _Grain_TilingParams.zw).r;
                grain = (grain - 0.5) * 2.0;
                // 按场景亮度调整颗粒感
                float lum = Luminance(inputColor);
                lum = 1.0 - sqrt(lum);
                lum = mix(1.0, lum, _Grain_Params.y);
                return inputColor + inputColor * grain * _Grain_Params.x * lum;
            }

            #ifdef FRAGMENT
            void main()
            {
                vec2 uvDistorted = DistortUV(uv);
                vec3 color;
                if (_Chroma_Params > 0.0)
                {
                    // 只用 3 次采样的快速色差：r/g/b 沿径向错开
                    vec2 coords = 2.0 * uv - 1.0;
                    vec2 end = uv - coords * dot(coords, coords) * _Chroma_Params;
                    vec2 delta = (end - uv) / 3.0;
                    float r = texture(_BlitTexture, uvDistorted).x;
                    float g = texture(_BlitTexture, DistortUV(delta + uv)).y;
                    float b = texture(_BlitTexture, DistortUV(delta * 2.0 + uv)).z;
                    color = vec3(r, g, b);
                }
                else
                    color = texture(_BlitTexture, uvDistorted).rgb;

                if (_BloomEnabled > 0.5)
                {
                    vec3 bloom = _BloomEnabled > 1.5
                        ? SampleTexture2DBicubic(_Bloom_Texture, uvDistorted, _Bloom_TexSize, vec2(1.0)).rgb
                        : texture(_Bloom_Texture, uvDistorted).rgb;
                    bloom *= _BloomParams.x;
                    color += bloom * _BloomParams.yzw;
                    if (_LensDirt_Intensity > 0.0)
                    {
                        vec3 dirt = texture(_LensDirt_Texture, uvDistorted * _LensDirt_Params.xy + _LensDirt_Params.zw).rgb;
                        dirt *= _LensDirt_Intensity;
                        color += dirt * bloom;
                    }
                }
                if (_Vignette2.z > 0.0)
                    color = ApplyVignette(color, uvDistorted, _Vignette2.xy, _Vignette2.z, _Vignette1.w, _Vignette2.w, _Vignette1.rgb);

                color = ApplyColorGrading(color);

                if (_GrainEnabled > 0.5)
                    color = ApplyGrain(color, uv);
                fragColor = vec4(color, 1.0);
            }
            #endif
            ENDGLSL
        }
    }
}
