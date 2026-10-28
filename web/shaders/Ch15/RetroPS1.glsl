// 复古像素风（PS1 风格）：顶点吸附到低分辨率网格、仿射纹理映射（不做透视校正）、（GLSL 版，对应 Ch15/RetroPS1.shader）
// 逐顶点光照、点采样，以及“抖动 + 色深量化”。每一项都能单独开关，方便对比。
Shader "Cookbook/Ch15/RetroPS1"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform vec4  _BaseMap_ST;
        uniform vec4  _BaseColor;
        uniform vec4  _VirtualRes;
        uniform float _VertexSnap, _Affine, _PointSample, _Quantize, _ColorBits;

        //#region snap
        // 把顶点吸附到 _VirtualRes 分辨率的像素格上。
        // 先除 w 得到 NDC，取整后再乘回 w，保持深度与透视不变，只让 xy 跳格。
        vec4 SnapToPixelGrid(vec4 positionCS, vec2 res)
        {
            vec2 halfRes = res * 0.5;
            vec2 ndc = positionCS.xy / positionCS.w;
            ndc = floor(ndc * halfRes + 0.5) / halfRes;
            positionCS.xy = ndc * positionCS.w;
            return positionCS;
        }
        //#endregion
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            GLSLPROGRAM
            uniform sampler2D _BaseMap;

            VARYING vec2 uv;          // 正常的（透视校正的）UV
            VARYING vec3 uvAffine;    // (uv * w, w)，用来抵消透视校正
            VARYING vec3 lighting;    // 逐顶点光照（Gouraud）

            #ifdef VERTEX
            void main()
            {
                vec3 positionWS = TransformObjectToWorld(positionOS.xyz);
                vec4 positionCS = TransformWorldToHClip(positionWS);
                if (_VertexSnap > 0.5) positionCS = SnapToPixelGrid(positionCS, _VirtualRes.xy);
                gl_Position = positionCS;

                uv = TransformTex(texcoord0.xy, _BaseMap_ST);
                //#region affine-vert
                // 透视校正插值对属性 A 实际做的是：插值 A/w 和 1/w 再相除。
                // 传入 A·w 和 w，两者都被“校正”后相除，w 抵消，剩下的就是屏幕空间线性插值的 A。
                uvAffine = vec3(uv * positionCS.w, positionCS.w);
                //#endregion

                // 逐顶点 Lambert + 环境光：当年的硬件只在顶点上算光
                vec3 N = TransformObjectToWorldNormal(normalOS);
                Light L = GetMainLight();
                lighting = saturate(dot(N, L.direction)) * L.color + SampleSH(N);
            }
            #endif

            #ifdef FRAGMENT
            //#region quantize
            const float kBayer4[16] = float[16](
                 0.0,  8.0,  2.0, 10.0,
                12.0,  4.0, 14.0,  6.0,
                 3.0, 11.0,  1.0,  9.0,
                15.0,  7.0, 13.0,  5.0);

            // 先加一个有序抖动偏移，再截断到 bits 位：渐变变成规则的网点而不是色带
            vec3 DitherQuantize(vec3 c, vec2 pixel, float bits)
            {
                ivec2 p = ivec2(mod(pixel, 4.0));
                float threshold = (kBayer4[p.y * 4 + p.x] + 0.5) / 16.0 - 0.5;   // -0.5..0.5
                float levels = exp2(bits) - 1.0;
                return floor(saturate(c) * levels + 0.5 + threshold) / levels;
            }
            //#endregion

            // HLSL 版用内联采样器 sampler_PointRepeat；GLSL 不能按调用换采样器，
            // 这里手动做“最近邻 + 最近 mip + 重复寻址”：先由导数估算 mip 级别，再 texelFetch
            vec4 SamplePointRepeat(sampler2D tex, vec2 st)
            {
                vec2 size0 = vec2(textureSize(tex, 0));
                vec2 dx = dFdx(st * size0), dy = dFdy(st * size0);
                float lod = 0.5 * log2(max(max(dot(dx, dx), dot(dy, dy)), 1e-8));
                int maxLod = int(log2(max(size0.x, size0.y)));
                int level = clamp(int(floor(lod + 0.5)), 0, maxLod);
                ivec2 size = textureSize(tex, level);
                ivec2 p = ivec2(fract(st) * vec2(size));
                return texelFetch(tex, clamp(p, ivec2(0), size - 1), level);
            }

            vec4 frag()
            {
                vec2 st = mix(uv, uvAffine.xy / uvAffine.z, _Affine);
                vec4 texLinear = texture(_BaseMap, st);
                vec4 texPoint  = SamplePointRepeat(_BaseMap, st);
                vec4 tex = mix(texLinear, texPoint, _PointSample);

                vec3 col = tex.rgb * _BaseColor.rgb * lighting;
                if (_Quantize > 0.5)
                {
                    // 抖动图案也按“虚拟分辨率”放大，模拟低分辨率帧缓冲上的抖动
                    vec2 virtualPixel = floor(gl_FragCoord.xy * _VirtualRes.xy / _ScreenParams.xy);
                    // 在 sRGB（显示）空间量化，色阶才均匀
                    col = SRGBToLinear(DitherQuantize(LinearToSRGB(col), virtualPixel, _ColorBits));
                }
                return vec4(col, 1.0);
            }
            void main() { fragColor = frag(); }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            GLSLPROGRAM
            // 深度也要按同样方式吸附，否则深度图与颜色错位
            #ifdef VERTEX
            void main()
            {
                vec4 positionCS = TransformObjectToHClip(positionOS.xyz);
                if (_VertexSnap > 0.5) positionCS = SnapToPixelGrid(positionCS, _VirtualRes.xy);
                gl_Position = positionCS;
            }
            #endif
            #ifdef FRAGMENT
            void main() { fragColor = vec4(0.0); }
            #endif
            ENDGLSL
        }
    }
}
