// 头发：Kajiya-Kay 双高光（Scheuermann 2004 的实时版本）。
// 发丝方向默认取网格切线 T；Unity 球体的切线是“横向”的，所以球形发帽要勾选 Strand Along V（用副切线做发丝方向）。
// （GLSL 版，对应 Ch12/HairKK.shader）
Shader "Cookbook/Ch12/HairKK"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform vec4  _ShiftTex_ST;
        uniform vec4  _BaseColor, _PrimaryColor, _SecondaryColor;
        uniform float _StrandAlongV, _ShiftAmount;
        uniform float _PrimaryShift, _PrimaryExp, _SecondaryShift, _SecondaryExp;
        uniform sampler2D _ShiftTex;
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }

            GLSLPROGRAM
            #pragma shader_feature_local_fragment _MODE_BLINNPHONG _MODE_SINGLE _MODE_DUAL

            #include "Ch12/Ch12Common.glsl"

            #ifdef VERTEX
            void main() { Ch12Vert(); }
            #endif

            #ifdef FRAGMENT
            struct MaterialCtx
            {
                vec3 N, V, T;
                vec3 albedo;
                float shiftNoise;   // 每根发丝的随机偏移
                float sparkle;      // 第二高光的闪烁遮罩
            };

            //#region shade
            vec3 ShadeOneLight(MaterialCtx m, Light light)
            {
                vec3 L = light.direction;
                vec3 H = normalize(L + m.V);
                float NoL = dot(m.N, L);

                // 漫反射：发丝是半透明细圆柱，Lambert 太“硬”，压一个下限让暗部不死黑
                vec3 diffuse = m.albedo * mix(0.25, 1.0, saturate(NoL));

                vec3 spec = vec3(0.0);
            #if defined(_MODE_BLINNPHONG)
                spec = _PrimaryColor.rgb * pow(saturate(dot(m.N, H)), _PrimaryExp * 0.5);
            #else
                vec3 t1 = AdvShiftTangent(m.T, m.N, _PrimaryShift + m.shiftNoise);
                spec = _PrimaryColor.rgb * AdvKajiyaKay(t1, H, _PrimaryExp);
              #if defined(_MODE_DUAL)
                vec3 t2 = AdvShiftTangent(m.T, m.N, _SecondaryShift + m.shiftNoise);
                spec += _SecondaryColor.rgb * m.sparkle * AdvKajiyaKay(t2, H, _SecondaryExp);
              #endif
            #endif
                // 背光面不给高光（发丝本身会挡住），用平滑过渡避免硬边
                spec *= smoothstep(-0.1, 0.3, NoL);

                return (diffuse + spec * 0.5) * light.color * (light.distanceAttenuation * light.shadowAttenuation);
            }
            //#endregion

            #include "Ch12/LightLoop.glsl"

            void main()
            {
                vec3 T, B, N; Ch12BuildFrame(T, B, N);
                vec3 V = GetWorldSpaceNormalizeViewDir(positionWS);
                vec2 screenUV = GetNormalizedScreenSpaceUV(gl_FragCoord);

                //#region strand
                MaterialCtx m;
                m.N = N; m.V = V;
                m.T = _StrandAlongV > 0.5 ? B : T;   // 发丝方向
                float n = texture(_ShiftTex, TransformTex(uv, _ShiftTex_ST)).r;
                m.shiftNoise = (n - 0.5) * _ShiftAmount;
                m.sparkle = saturate(n * 1.6 - 0.3);
                // 发丝颜色也带一点随机明暗，看起来才像一缕缕的
                m.albedo = _BaseColor.rgb * mix(0.7, 1.15, n);
                //#endregion

                vec3 color = AccumulateDirectLighting(m, positionWS, screenUV);
                color += SampleSH(N) * m.albedo;

                color = MixFog(color, fogFactor);
                fragColor = vec4(color, 1.0);
            }
            #endif
            ENDGLSL
        }

        UsePass "Cookbook/Common/SHADOWCASTER"
        UsePass "Cookbook/Common/DEPTHONLY"
        UsePass "Cookbook/Common/DEPTHNORMALS"
    }
}
