// 播放 VAT：顶点用 uv1.x（自己的编号）+ 当前帧号去查位置/法线贴图，相邻两帧之间线性插值。（GLSL 版）
// 帧号 = _Time.y * _FPS + _Frame；静帧时 _Time≈0，直接用 _Frame 指定。
Shader "Cookbook/Ch17/VAT"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform float _FPS, _Frame;
        uniform vec4 _RootColor, _TipColor;
        uniform vec4 _PosTex_TexelSize;      // (1/宽, 1/高, 宽, 高)：高 = 帧数
        uniform highp sampler2D _PosTex;
        uniform highp sampler2D _NrmTex;
        #include "Ch17/VertexAnimCommon.glsl"

        // HLSL 的 fmod：结果与被除数同号（GLSL 的 mod 对负数不同）
        float fmodHLSL(float a, float b) { return a - b * trunc(a / b); }

        // GLSL 不能按调用指定采样器（sampler_PointClamp）：点采样直接用 texelFetch 取纹素
        vec4 SamplePoint(highp sampler2D tex, vec2 uv)
        {
            ivec2 size = textureSize(tex, 0);
            ivec2 p = clamp(ivec2(uv * vec2(size)), ivec2(0), size - 1);
            return texelFetch(tex, p, 0);
        }

        //#region deform
        void Deform(inout VAAttributes v)
        {
            float frames = _PosTex_TexelSize.w;
            float f = fmodHLSL(_Time.y * _FPS + _Frame, frames);
            float f0 = floor(f);
            float f1 = fmodHLSL(f0 + 1.0, frames);   // 最后一帧插值回第一帧，循环无缝
            float w = f - f0;

            // 采样纹素中心；必须用点采样 + LOD 0，否则相邻顶点/相邻帧会被双线性混在一起
            vec2 uv0 = vec2(v.uv1.x, (f0 + 0.5) / frames);
            vec2 uv1 = vec2(v.uv1.x, (f1 + 0.5) / frames);
            vec3 p0 = SamplePoint(_PosTex, uv0).xyz;
            vec3 p1 = SamplePoint(_PosTex, uv1).xyz;
            vec3 n0 = SamplePoint(_NrmTex, uv0).xyz;
            vec3 n1 = SamplePoint(_NrmTex, uv1).xyz;

            v.positionOS.xyz = mix(p0, p1, w);       // 贴图里存的是绝对位置，直接替换
            v.normalOS = normalize(mix(n0, n1, w));
        }
        //#endregion

        #include "Ch17/VertexAnimPasses.glsl"
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            GLSLPROGRAM
            #ifdef VERTEX
            void main() { VAForwardVert(); }
            #endif
            #ifdef FRAGMENT
            void main()
            {
                vec3 albedo = mix(_RootColor.rgb, _TipColor.rgb, uv.y);
                // 横向的环纹，方便看出扭转
                albedo *= 0.8 + 0.2 * step(0.5, fract(uv.x * 4.0));
                fragColor = vec4(VALighting(albedo, normalize(normalWS), positionWS, 0.6, 48.0), 1.0);
            }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0
            GLSLPROGRAM
            #ifdef VERTEX
            void main() { VAShadowVert(); }
            #endif
            #ifdef FRAGMENT
            void main() { VANullFrag(); }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            GLSLPROGRAM
            #ifdef VERTEX
            void main() { VADepthVert(); }
            #endif
            #ifdef FRAGMENT
            void main() { VANullFrag(); }
            #endif
            ENDGLSL
        }
    }
}
