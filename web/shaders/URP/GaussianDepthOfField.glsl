// URP 14 GaussianDepthOfField.shader 的 GLSL 版：只模糊远景（近处不处理）。
// 流程：全分辨率 CoC → 半分辨率预过滤（颜色 × CoC）→ 横向/纵向高斯 → 合成。
// URP 的预过滤用 MRT 同时输出 CoC 和颜色，WebGL 这里拆成两个 Pass，算法相同。
Shader "Hidden/Universal Render Pipeline/GaussianDepthOfField"
{
    SubShader
    {
        ZTest Always ZWrite Off Cull Off
        GLSLINCLUDE
        VARYING vec2 uv;
        #ifdef VERTEX
        void main()
        {
            vec2 p = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);
            uv = p;
            gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
        }
        #endif
        uniform sampler2D _ColorTexture;
        uniform sampler2D _FullCoCTexture;
        uniform sampler2D _HalfCoCTexture;
        uniform vec4 _SourceSize;              // (宽, 高, 1/宽, 1/高)，全分辨率
        uniform vec4 _DownSampleScaleFactor;   // (1/2, 1/2, 2, 2)
        uniform vec4 _CoCParams;               // (远景开始, 远景结束, 最大半径)
        uniform float _HighQualitySampling;
        #define FarStart  _CoCParams.x
        #define FarEnd    _CoCParams.y
        #define MaxRadius _CoCParams.z

        const float kOffsets[3] = float[3](-1.33333333, 0.0, 1.33333333);
        const float kCoeffs[3] = float[3](0.35294118, 0.29411765, 0.35294118);

        // 预过滤：高质量时 5 次采样（颜色按 CoC 加权）
        void Prefilter(out float farCoC, out vec3 color)
        {
            if (_HighQualitySampling > 0.5)
            {
                vec2 kTaps[5] = vec2[5](vec2(0.0, 0.0), vec2(0.9, -0.4), vec2(-0.9, 0.4), vec2(0.4, 0.9), vec2(-0.4, -0.9));
                vec3 colorAcc = vec3(0.0);
                float farCoCAcc = 0.0;
                for (int i = 0; i < 5; i++)
                {
                    vec2 tapCoord = _SourceSize.zw * kTaps[i] + uv;
                    vec3 tapColor = texture(_BlitTexture, tapCoord).xyz;
                    float coc = texture(_FullCoCTexture, tapCoord).x;
                    colorAcc += tapColor * coc;
                    farCoCAcc += coc;
                }
                color = colorAcc / 5.0;
                farCoC = farCoCAcc / 5.0;
            }
            else
            {
                farCoC = texture(_FullCoCTexture, uv).x;
                color = texture(_BlitTexture, uv).xyz * farCoC;
            }
        }

        vec4 Blur(vec2 dir, float premultiply)
        {
            ivec2 positionSS = ivec2(_SourceSize.xy * _DownSampleScaleFactor.xy * uv);
            float samp0CoC = texelFetch(_HalfCoCTexture, positionSS, 0).x;
            vec2 offset = _SourceSize.zw * _DownSampleScaleFactor.zw * dir * samp0CoC * MaxRadius;
            vec4 acc = vec4(0.0);
            for (int i = 0; i < 3; i++)
            {
                vec2 sampCoord = uv + kOffsets[i] * offset;
                float sampCoC = texture(_HalfCoCTexture, sampCoord).x;
                vec3 sampColor = texture(_BlitTexture, sampCoord).xyz;
                // 权重：别让清晰的前景渗进模糊的背景
                float weight = saturate(1.0 - (samp0CoC - sampCoC));
                acc += vec4(sampColor, premultiply > 0.5 ? sampCoC : 1.0) * kCoeffs[i] * weight;
            }
            acc.xyz /= acc.w + 1e-4;
            return vec4(acc.xyz, 1.0);
        }
        ENDGLSL

        Pass
        {
            Name "Gaussian Depth Of Field CoC"
            GLSLPROGRAM
            #ifdef FRAGMENT
            void main()
            {
                float depth = texelFetch(_CameraDepthTexture, ivec2(_SourceSize.xy * uv), 0).x;
                depth = LinearEyeDepth(depth, _ZBufferParams);
                float coc = (depth - FarStart) / (FarEnd - FarStart);
                fragColor = vec4(saturate(coc));
            }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "Gaussian Depth Of Field Prefilter CoC"
            GLSLPROGRAM
            #ifdef FRAGMENT
            void main() { float coc; vec3 c; Prefilter(coc, c); fragColor = vec4(coc); }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "Gaussian Depth Of Field Prefilter Color"
            GLSLPROGRAM
            #ifdef FRAGMENT
            void main() { float coc; vec3 c; Prefilter(coc, c); fragColor = vec4(c, 1.0); }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "Gaussian Depth Of Field Blur Horizontal"
            GLSLPROGRAM
            #ifdef FRAGMENT
            void main() { fragColor = Blur(vec2(1.0, 0.0), 1.0); }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "Gaussian Depth Of Field Blur Vertical"
            GLSLPROGRAM
            #ifdef FRAGMENT
            void main() { fragColor = Blur(vec2(0.0, 1.0), 0.0); }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "Gaussian Depth Of Field Composite"
            GLSLPROGRAM
            #include "URP/PostFXCommon.glsl"
            #ifdef FRAGMENT
            void main()
            {
                vec3 baseColor = texelFetch(_BlitTexture, ivec2(_SourceSize.xy * uv), 0).xyz;
                float coc = texelFetch(_FullCoCTexture, ivec2(_SourceSize.xy * uv), 0).x;
                vec3 farColor = _HighQualitySampling > 0.5
                    ? SampleTexture2DBicubic(_ColorTexture, uv, _SourceSize * _DownSampleScaleFactor, vec2(1.0)).xyz
                    : texture(_ColorTexture, uv).xyz;
                vec3 dstColor = vec3(0.0);
                float dstAlpha = 1.0;
                if (coc > 0.0)
                {
                    float blend = sqrt(coc * TWO_PI);
                    dstColor = farColor * saturate(blend);
                    dstAlpha = saturate(1.0 - blend);
                }
                fragColor = vec4(baseColor * dstAlpha + dstColor, 1.0);
            }
            #endif
            ENDGLSL
        }
    }
}
