// 膨胀 / 呼吸：沿某个方向把顶点推出去。（GLSL 版）
//   方向 = 网格法线：最简单，但硬边模型（立方体）的同一位置有多个法线不同的顶点，推开后会裂缝；
//   方向 = 从中心指向顶点：同一位置的顶点方向相同，硬边不会裂开（适合大致凸的形体）。
// 呼吸：振幅随时间做正弦，相位再加上沿 Y 的偏移，就成了一道从下往上走的“脉冲”。
Shader "Cookbook/Ch17/Inflate"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        #pragma shader_feature_local_vertex _DIR_NORMAL _DIR_RADIAL
        uniform vec4 _BaseColor;
        uniform float _Amount, _PulseFreq, _Speed, _Phase;
        #include "Ch17/VertexAnimCommon.glsl"

        //#region deform
        void Deform(inout VAAttributes v)
        {
        #if defined(_DIR_RADIAL)
            vec3 dir = normalize(v.positionOS.xyz);       // 同一位置 → 同一方向，硬边不裂
        #else
            vec3 dir = v.normalOS;
        #endif
            // 呼吸：0..1 之间往复；_PulseFreq > 0 时不同高度相位不同，形成向上传播的脉冲
            float t = _Time.y * _Speed + _Phase;
            float breath = sin(t - v.positionOS.y * _PulseFreq) * 0.5 + 0.5;
            v.positionOS.xyz += dir * _Amount * breath;
            // 均匀膨胀不改变光滑表面的法线方向，这里保持原法线
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
                fragColor = vec4(VALighting(_BaseColor.rgb, normalize(normalWS), positionWS, 0.5, 48.0), 1.0);
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
