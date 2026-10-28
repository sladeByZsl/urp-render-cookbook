// 卡通头发 + 天使环（Angel Ring）。（GLSL 版，对应 Ch14/ToonHair.shader）
// 天使环本质是 Kajiya-Kay 发丝高光的“色阶化”：一条沿头顶环绕的硬边亮带，边缘用噪声切成锯齿。
Shader "Cookbook/Ch14/ToonHair"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform vec4 _ShiftTex_ST;
        uniform vec4 _BaseColor, _ShadeColor, _RingColor;
        uniform float _RingShift, _RingExponent, _RingThreshold, _RingNoise, _RingFollowView, _StrandAlongV;
        uniform vec4 _OutlineColor;
        uniform float _OutlineWidth;
        uniform sampler2D _ShiftTex;
        ENDGLSL

        Pass
        {
            Name "ToonForward"
            Tags { "LightMode"="UniversalForwardOnly" }

            GLSLPROGRAM
            #pragma shader_feature_local_fragment _RING_OFF _RING_SMOOTH _RING_TOON
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
                vec3 Tm = normalize(tangentWS.xyz);
                vec3 Bm = cross(N, Tm) * tangentWS.w;
                vec3 T = _StrandAlongV > 0.5 ? Bm : Tm;          // 发丝方向
                vec3 V = GetWorldSpaceNormalizeViewDir(positionWS);
                Light light = GetMainLight();

                float band = ToonBand(dot(N, light.direction) * 0.5 + 0.5, 0.5, 0.02);
                vec3 color = mix(_ShadeColor.rgb, _BaseColor.rgb, band) * light.color;
                color += SampleSH(vec3(0.0)) * _BaseColor.rgb * 0.3;

                // 天使环的“光源”：可以跟主光走，也可以固定在相机上方——后者让环始终出现在头顶，
                // 这是很多二次元项目的选择（美术要的是稳定的造型，而不是物理正确）
                vec3 viewUp = normalize(UNITY_MATRIX_I_V[1].xyz);   // 逆观察矩阵的第 2 列 = 相机的“上”（HLSL 的 _m01_m11_m21）
                vec3 Lring = normalize(mix(light.direction, normalize(V + viewUp * 0.6), _RingFollowView));
                vec3 H = normalize(Lring + V);

                float noise = texture(_ShiftTex, TransformTex(uv, _ShiftTex_ST)).r;
                float shift = _RingShift + (noise - 0.5) * _RingNoise;   // 每缕头发偏移不同 → 锯齿边
                float s = StrandSpecular(T, N, H, shift, _RingExponent);

                float ring = 0.0;
            #if defined(_RING_SMOOTH)
                ring = s;                                               // 写实版：连续的发丝高光
            #elif defined(_RING_TOON)
                ring = ToonBand(s, _RingThreshold, 0.02);               // 卡通版：切成硬边色块
            #endif
                color = mix(color, _RingColor.rgb * mix(0.6, 1.0, band), ring * 0.9);

                return vec4(MixFog(color, fogFactor), 1.0);
            }
            //#endregion
            void main() { fragColor = frag(); }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "Outline"
            Tags { "LightMode"="SRPDefaultUnlit" }
            Cull Front
            ZWrite On
            GLSLPROGRAM
            #include "Ch14/ToonOutlinePass.glsl"
            ENDGLSL
        }

        UsePass "Cookbook/Common/SHADOWCASTER"
        UsePass "Cookbook/Common/DEPTHONLY"
        UsePass "Cookbook/Common/DEPTHNORMALS"
    }
}
