// 旗帜飘动：在细分平面（物体空间 XZ 平面，法线 +Y）上沿 Y 方向位移。（GLSL 版）
// 位移 = 沿旗面传播的正弦波 + 噪声扰动，振幅从旗杆处的 0 逐渐增大；
// 法线用有限差分重新计算（对位移函数在 x、z 方向各取一个邻点）。
Shader "Cookbook/Ch17/Flag"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform vec4 _BaseMap_ST;
        uniform vec4 _BaseColor;
        uniform float _Amplitude, _WaveLength, _Speed, _NoiseStrength, _Phase, _FlagWidth, _RecalcNormal, _DeformShadow;
        uniform sampler2D _BaseMap;
        uniform sampler2D _NoiseTex;
        #include "Ch17/VertexAnimCommon.glsl"

        //#region displace
        // 位移只依赖旗面上的 (x, z) 坐标和时间：这是能用有限差分求法线的前提
        float FlagOffset(vec2 xz)
        {
            float u = xz.x / _FlagWidth + 0.5;             // 0 = 旗杆一侧，1 = 自由端
            float t = _Time.y * _Speed + _Phase;           // 运行时 _Time 驱动；静帧用 _Phase
            float k = TWO_PI / _WaveLength;
            float pin = smoothstep(0.0, 0.25, u) * u;      // 旗杆处钉死，越往外摆得越大
            // 主波沿 +x 传播，次波斜向传播，让波峰不那么整齐
            float w = sin(k * xz.x - t) + 0.35 * sin(k * 1.7 * (xz.x * 0.6 + xz.y) - t * 1.3);
            // 噪声：随时间平移，制造“阵风”造成的不规则起伏
            vec2 nuv = xz * 0.12 + vec2(-t * 0.05, t * 0.02);   // 低频采样：只要大尺度的起伏
            float n = textureLod(_NoiseTex, nuv, 0.0).r * 2.0 - 1.0;
            return (w + n * _NoiseStrength * 2.0) * _Amplitude * pin;
        }
        //#endregion

        //#region deform
        void Deform(inout VAAttributes v)
        {
            vec3 p = v.positionOS.xyz;
            float h = FlagOffset(p.xz);

            if (_RecalcNormal > 0.5)
            {
                // 有限差分：在 x、z 方向各挪一小步，得到两个“切线”，叉乘就是新法线
                const float e = 0.04;   // 步长太小会放大噪声贴图的双线性折痕
                float hx = FlagOffset(p.xz + vec2(e, 0.0));
                float hz = FlagOffset(p.xz + vec2(0.0, e));
                vec3 tangent   = vec3(e, hx - h, 0.0);
                vec3 bitangent = vec3(0.0, hz - h, e);
                v.normalOS = normalize(cross(bitangent, tangent));
            }
            v.positionOS.y += h;
        }

        // 阴影 Pass 专用：_DeformShadow = 0 时不变形，用来演示“影子不动”的错误
        void DeformForShadow(inout VAAttributes v)
        {
            if (_DeformShadow > 0.5) Deform(v);
        }
        #define VA_DEFORM_SHADOW DeformForShadow
        //#endregion

        #include "Ch17/VertexAnimPasses.glsl"
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            Cull Off
            GLSLPROGRAM
            #ifdef VERTEX
            void main() { VAForwardVert(); }
            #endif
            #ifdef FRAGMENT
            void main()
            {
                vec3 N = normalize(normalWS) * (gl_FrontFacing ? 1.0 : -1.0);   // 旗子两面都要正确受光
                vec3 albedo = texture(_BaseMap, TransformTex(uv, _BaseMap_ST)).rgb * _BaseColor.rgb;
                fragColor = vec4(VALighting(albedo, N, positionWS, 0.25, 24.0), 1.0);
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
