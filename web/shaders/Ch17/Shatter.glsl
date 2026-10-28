// 碎裂与吸附重组：每个三角形是一块碎片，围绕自己的中心旋转、沿面法线飞出并受“重力”下落。（GLSL 版）
// _Progress 从 0 到 1 是碎裂；反过来从 1 到 0 播放，就是碎片飞回来“吸附”成形。
// 碎片开始运动的时间由它在 _SweepDir 方向上的位置决定，形成一道扫过模型的“裂解前沿”。
Shader "Cookbook/Ch17/Shatter"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform vec4 _BaseColor, _GlowColor;
        uniform vec4 _SweepDir;
        uniform float _Progress, _Spread, _Distance, _Spin, _Gravity, _Shrink;
        #include "Ch17/VertexAnimCommon.glsl"

        // URP Core 的 GeometricTools.hlsl 里的 RotationFromAxisAngle（绕单位轴 A 旋转）。
        // HLSL 的 float3x3(...) 按行构造，GLSL 的 mat3(...) 按列构造，所以外面套一个 transpose
        mat3 RotationFromAxisAngle(vec3 A, float sinAngle, float cosAngle)
        {
            float c = cosAngle, s = sinAngle;
            return transpose(mat3(
                A.x * A.x * (1.0 - c) + c,       A.x * A.y * (1.0 - c) - A.z * s, A.x * A.z * (1.0 - c) + A.y * s,
                A.x * A.y * (1.0 - c) + A.z * s, A.y * A.y * (1.0 - c) + c,       A.y * A.z * (1.0 - c) - A.x * s,
                A.x * A.z * (1.0 - c) - A.y * s, A.y * A.z * (1.0 - c) + A.x * s, A.z * A.z * (1.0 - c) + c));
        }

        //#region deform
        void Deform(inout VAAttributes v)
        {
            vec3 center = v.uv1.xyz;
            float rnd = v.uv1.w;
            vec3 faceN = v.uv2.xyz;

            // 1) 这块碎片自己的进度 p：沿扫描方向越靠前越早开始，再加一点随机
            // 物体空间坐标大致在 -1..1，映射到 0..1 后乘以 _Spread
            float start = saturate(dot(center, normalize(_SweepDir.xyz)) * 0.5 + 0.5) * _Spread + rnd * 0.2;
            float p = saturate(_Progress * (1.0 + _Spread + 0.2) - start);
            float ease = p * p * (3.0 - 2.0 * p);                  // smoothstep 曲线，起步柔和

            // 2) 绕碎片中心、绕一根随机轴旋转，并逐渐缩小
            vec3 axis = normalize(vec3(rnd - 0.5, fract(rnd * 7.13) - 0.5, fract(rnd * 3.71) - 0.5) + 1e-4);
            float angle = ease * _Spin * (0.5 + rnd);
            mat3 R = RotationFromAxisAngle(axis, sin(angle), cos(angle));
            vec3 local = (R * (v.positionOS.xyz - center)) * (1.0 - ease * _Shrink);

            // 3) 沿面法线飞出 + 抛物线下落（物体空间的 -Y）
            vec3 offset = faceN * ease * _Distance * (0.6 + rnd) + vec3(0.0, 1.0, 0.0) * (0.3 * ease - _Gravity * ease * ease);

            v.positionOS.xyz = center + local + offset;
            v.normalOS = R * v.normalOS;                         // 法线跟着碎片一起转
            v.uv2.w = p;                                         // 进度交给片元做发光
        }
        //#endregion

        #include "Ch17/VertexAnimPasses.glsl"
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            Cull Off    // 碎片翻转后会露出背面
            GLSLPROGRAM
            #ifdef VERTEX
            void main() { VAForwardVert(); }
            #endif
            #ifdef FRAGMENT
            void main()
            {
                vec3 N = normalize(normalWS) * (gl_FrontFacing ? 1.0 : -1.0);
                vec3 col = VALighting(_BaseColor.rgb, N, positionWS, 0.6, 64.0);
                // 刚脱离的碎片最亮，飞远后逐渐冷却
                float p = extra.w;
                float glow = saturate(p * 6.0) * (1.0 - p);
                fragColor = vec4(col + _GlowColor.rgb * glow, 1.0);
            }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0 Cull Off
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
            ZWrite On ColorMask R Cull Off
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
