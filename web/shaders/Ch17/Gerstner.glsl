// Gerstner 波（又称 Trochoidal 波）：水面上的点不只上下动，还沿传播方向前后做圆周运动，（GLSL 版）
// 于是波峰变尖、波谷变平。最多叠加 4 个波，法线由解析偏导数求得，泡沫来自雅可比行列式。
Shader "Cookbook/Ch17/Gerstner"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform vec4 _DeepColor, _ShallowColor, _FoamColor;
        uniform vec4 _WaveA, _WaveB, _WaveC, _WaveD;
        uniform float _Horizontal, _FoamThreshold, _Phase;
        #include "Ch17/VertexAnimCommon.glsl"

        //#region gerstner
        // 累加一个 Gerstner 波。x0：未扰动时的水平位置（世界 xz）。
        // 返回位移；同时累加对 x、z 的偏导数，用于求法线和雅可比行列式。
        vec3 GerstnerWave(vec4 wave, vec2 x0, float t, inout vec3 dPdx, inout vec3 dPdz)
        {
            float steep = wave.z;
            if (steep <= 0.0) return vec3(0.0);
            float k = TWO_PI / wave.w;                 // 波数
            float omega = sqrt(9.8 * k);               // 深水色散关系 ω² = g·k
            vec2 D = normalize(wave.xy);
            float theta = k * dot(D, x0) - omega * t;
            float a = steep / k;                       // 振幅：陡度 = k·a，k·a = 1 时波峰恰好成尖角
            float s = sin(theta), c = cos(theta);      // HLSL 的 sincos
            float h = _Horizontal;                     // 0 = 退化为普通正弦波（只有竖直位移）

            // 位移：水平方向 D·a·cosθ，竖直方向 a·sinθ
            vec3 offset = vec3(D.x * a * c * h, a * s, D.y * a * c * h);

            // 偏导数（对 x0.x、x0.z 求导，注意 ∂θ/∂x = k·D.x）
            dPdx += vec3(-D.x * D.x * steep * s * h, D.x * steep * c, -D.x * D.y * steep * s * h);
            dPdz += vec3(-D.x * D.y * steep * s * h, D.y * steep * c, -D.y * D.y * steep * s * h);
            return offset;
        }
        //#endregion

        //#region deform
        void Deform(inout VAAttributes v)
        {
            vec3 positionWS = TransformObjectToWorld(v.positionOS.xyz);
            vec2 x0 = positionWS.xz;
            float t = _Time.y + _Phase;
            vec3 dPdx = vec3(1, 0, 0), dPdz = vec3(0, 0, 1);   // 平面本身的偏导数
            vec3 offset = GerstnerWave(_WaveA, x0, t, dPdx, dPdz)
                        + GerstnerWave(_WaveB, x0, t, dPdx, dPdz)
                        + GerstnerWave(_WaveC, x0, t, dPdx, dPdz)
                        + GerstnerWave(_WaveD, x0, t, dPdx, dPdz);
            positionWS += offset;

            // 法线 = ∂P/∂z × ∂P/∂x（Unity 左手系里这个顺序朝上）
            vec3 normalWS = normalize(cross(dPdz, dPdx));
            // 雅可比行列式：水平面被“挤压”的程度。< 1 表示表面被压缩，接近 0 时波峰要翻卷，正是起泡沫的地方
            float jacobian = dPdx.x * dPdz.z - dPdx.z * dPdz.x;

            v.positionOS.xyz = TransformWorldToObject(positionWS);
            v.normalOS = TransformWorldToObjectNormal(normalWS);
            v.uv2 = vec4(jacobian, offset.y, 0.0, 0.0);
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
            //#region frag
            void main()
            {
                vec3 N = normalize(normalWS);
                vec3 V = GetWorldSpaceNormalizeViewDir(positionWS);
                Light L = GetMainLight(TransformWorldToShadowCoord(positionWS));

                // 水体颜色：越高（波峰）越浅，模拟光在薄水层里的透射
                float crest = saturate(extra.y * 0.8 + 0.5);
                vec3 water = mix(_DeepColor.rgb, _ShallowColor.rgb, crest * crest);
                vec3 col = water * (saturate(dot(N, L.direction)) * 0.5 + 0.5) * (L.color * L.shadowAttenuation * 0.6 + SampleSH(N));

                // 菲涅尔反射天空（水的 F0 约 0.02）
                float fresnel = 0.02 + 0.98 * pow(1.0 - saturate(dot(N, V)), 5.0);
                vec3 refl = GlossyEnvironmentReflection(reflect(-V, N), 0.05, 1.0);
                col = mix(col, refl, fresnel);

                // 太阳高光
                vec3 H = normalize(L.direction + V);
                col += pow(saturate(dot(N, H)), 400.0) * 6.0 * L.color * L.shadowAttenuation;

                // 泡沫：雅可比行列式越小（越被压缩）泡沫越多
                float foam = saturate((_FoamThreshold - extra.x) / max(_FoamThreshold, 1e-3) * 2.0);
                col = mix(col, _FoamColor.rgb * (SampleSH(N) + L.color * 0.6), foam);
                fragColor = vec4(col, 1.0);
            }
            //#endregion
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
