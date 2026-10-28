// URP 14 BokehDepthOfField.shader 的 GLSL 版：按物理相机参数（焦距、光圈、对焦距离）算弥散圆，
// 半分辨率下用 42 个采样点的多边形核（光圈叶片）做散景，前景/背景分开累积，最后合成。
Shader "Hidden/Universal Render Pipeline/BokehDepthOfField"
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
        #define SAMPLE_COUNT 42
        uniform sampler2D _DofTexture;
        uniform sampler2D _FullCoCTexture;
        uniform vec4 _SourceSize;              // (宽, 高, 1/宽, 1/高)，全分辨率
        uniform vec4 _DownSampleScaleFactor;   // (1/2, 1/2, 2, 2)
        uniform vec4 _CoCParams;               // (对焦距离, 最大 CoC, 最大半径, 1/宽高比)
        uniform vec4 _BokehKernel[SAMPLE_COUNT];
        uniform vec4 _BokehConstants;          // (uvMargin, uvMargin*2)
        #define FocusDist _CoCParams.x
        #define MaxCoC    _CoCParams.y
        #define MaxRadius _CoCParams.z
        #define RcpAspect _CoCParams.w
        float Max3(float a, float b, float c) { return max(a, max(b, c)); }
        float Min3(float a, float b, float c) { return min(a, min(b, c)); }
        ENDGLSL

        Pass
        {
            Name "Bokeh Depth Of Field CoC"
            GLSLPROGRAM
            #ifdef FRAGMENT
            void main()
            {
                float depth = texelFetch(_CameraDepthTexture, ivec2(_SourceSize.xy * uv), 0).x;
                float linearEyeDepth = LinearEyeDepth(depth, _ZBufferParams);
                float coc = (1.0 - FocusDist / linearEyeDepth) * MaxCoC;
                float nearCoC = clamp(coc, -1.0, 0.0);
                float farCoC = saturate(coc);
                // 存成 0~1：0.5 = 清晰，< 0.5 前景，> 0.5 背景
                fragColor = vec4(saturate((farCoC + nearCoC + 1.0) * 0.5));
            }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "Bokeh Depth Of Field Prefilter"
            GLSLPROGRAM
            #ifdef FRAGMENT
            void main()
            {
                // 降到半分辨率：取 2×2 个全分辨率像素
                vec3 duv = _SourceSize.zwz * vec3(0.5, 0.5, -0.5);
                vec2 uv0 = uv - duv.xy, uv1 = uv - duv.zy, uv2 = uv + duv.zy, uv3 = uv + duv.xy;
                vec3 c0 = texture(_BlitTexture, uv0).xyz;
                vec3 c1 = texture(_BlitTexture, uv1).xyz;
                vec3 c2 = texture(_BlitTexture, uv2).xyz;
                vec3 c3 = texture(_BlitTexture, uv3).xyz;
                float coc0 = texture(_FullCoCTexture, uv0).x * 2.0 - 1.0;
                float coc1 = texture(_FullCoCTexture, uv1).x * 2.0 - 1.0;
                float coc2 = texture(_FullCoCTexture, uv2).x * 2.0 - 1.0;
                float coc3 = texture(_FullCoCTexture, uv3).x * 2.0 - 1.0;
                vec3 avg = (c0 + c1 + c2 + c3) / 4.0;
                float cocMin = min(coc0, Min3(coc1, coc2, coc3));
                float cocMax = max(coc0, Max3(coc1, coc2, coc3));
                float coc = (-cocMin > cocMax ? cocMin : cocMax) * MaxRadius;
                // 清晰区域的颜色不参与散景
                avg *= smoothstep(0.0, _SourceSize.w * 2.0, abs(coc));
                fragColor = vec4(avg, coc);
            }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "Bokeh Depth Of Field Blur"
            GLSLPROGRAM
            void Accumulate(vec4 samp0, vec2 uv, vec4 disp, inout vec4 farAcc, inout vec4 nearAcc)
            {
                vec4 samp = texture(_BlitTexture, uv + disp.wy);
                // 背景：取两者中较小的 CoC，避免清晰的前景被背景“吃掉”
                float farCoC = max(min(samp0.a, samp.a), 0.0);
                float farWeight = saturate((farCoC - disp.z + _BokehConstants.y) / _BokehConstants.y);
                float nearWeight = saturate((-samp.a - disp.z + _BokehConstants.y) / _BokehConstants.y);
                nearWeight *= step(_BokehConstants.x, -samp.a);
                farAcc += vec4(samp.rgb, 1.0) * farWeight;
                nearAcc += vec4(samp.rgb, 1.0) * nearWeight;
            }
            #ifdef FRAGMENT
            void main()
            {
                vec4 samp0 = texture(_BlitTexture, uv);
                vec4 farAcc = vec4(0.0), nearAcc = vec4(0.0);
                Accumulate(samp0, uv, vec4(0.0), farAcc, nearAcc);
                for (int si = 0; si < SAMPLE_COUNT; si++)
                    Accumulate(samp0, uv, _BokehKernel[si], farAcc, nearAcc);
                farAcc.rgb /= farAcc.a + (farAcc.a == 0.0 ? 1.0 : 0.0);
                nearAcc.rgb /= nearAcc.a + (nearAcc.a == 0.0 ? 1.0 : 0.0);
                nearAcc.a *= PI / float(SAMPLE_COUNT + 1);
                float alpha = saturate(nearAcc.a);
                vec3 rgb = mix(farAcc.rgb, nearAcc.rgb, alpha);
                fragColor = vec4(rgb, alpha);
            }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "Bokeh Depth Of Field Post Blur"
            GLSLPROGRAM
            #ifdef FRAGMENT
            void main()
            {
                vec4 duv = _SourceSize.zwzw * _DownSampleScaleFactor.zwzw * vec4(0.5, 0.5, -0.5, 0.0);
                vec4 acc = texture(_BlitTexture, uv - duv.xy);
                acc += texture(_BlitTexture, uv - duv.zy);
                acc += texture(_BlitTexture, uv + duv.zy);
                acc += texture(_BlitTexture, uv + duv.xy);
                fragColor = acc * 0.25;
            }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "Bokeh Depth Of Field Composite"
            GLSLPROGRAM
            #ifdef FRAGMENT
            void main()
            {
                vec4 dof = texture(_DofTexture, uv);
                float coc = texture(_FullCoCTexture, uv).r;
                coc = (coc - 0.5) * 2.0 * MaxRadius;
                float ffa = smoothstep(_SourceSize.w * 2.0, _SourceSize.w * 4.0, coc);
                vec4 color = texture(_BlitTexture, uv);
                float alpha = Max3(dof.r, dof.g, dof.b);
                color = mix(color, vec4(dof.rgb, alpha), ffa + dof.a - ffa * dof.a);
                fragColor = color;
            }
            #endif
            ENDGLSL
        }
    }
}
