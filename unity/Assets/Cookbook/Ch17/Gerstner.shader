// Gerstner 波（又称 Trochoidal 波）：水面上的点不只上下动，还沿传播方向前后做圆周运动，
// 于是波峰变尖、波谷变平。最多叠加 4 个波，法线由解析偏导数求得，泡沫来自雅可比行列式。
Shader "Cookbook/Ch17/Gerstner"
{
    Properties
    {
        _DeepColor ("Deep Color", Color) = (0.02, 0.12, 0.2, 1)
        _ShallowColor ("Crest Color", Color) = (0.1, 0.45, 0.55, 1)
        _FoamColor ("Foam Color", Color) = (0.9, 0.95, 1, 1)
        // 每个波：xy = 传播方向，z = 陡度 steepness（0..1），w = 波长（米）
        _WaveA ("Wave A (dir.xy, steepness, wavelength)", Vector) = (1, 0, 0.5, 4)
        _WaveB ("Wave B", Vector) = (0, 1, 0.25, 3)
        _WaveC ("Wave C", Vector) = (1, 1, 0.15, 1.6)
        _WaveD ("Wave D", Vector) = (-0.6, 1, 0.1, 0.9)
        [Toggle] _Horizontal ("Horizontal Displacement (Gerstner)", Float) = 1
        _FoamThreshold ("Foam Threshold (Jacobian)", Range(0, 1)) = 0.35
        _Phase ("Phase (seconds, for stills)", Float) = 0
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        CBUFFER_START(UnityPerMaterial)
            half4 _DeepColor, _ShallowColor, _FoamColor;
            float4 _WaveA, _WaveB, _WaveC, _WaveD;
            float _Horizontal, _FoamThreshold, _Phase;
        CBUFFER_END
        #include "Assets/Cookbook/Ch17/VertexAnimCommon.hlsl"

        //#region gerstner
        // 累加一个 Gerstner 波。x0：未扰动时的水平位置（世界 xz）。
        // 返回位移；同时累加对 x、z 的偏导数，用于求法线和雅可比行列式。
        float3 GerstnerWave(float4 wave, float2 x0, float t, inout float3 dPdx, inout float3 dPdz)
        {
            float steep = wave.z;
            if (steep <= 0) return 0;
            float k = TWO_PI / wave.w;                 // 波数
            float omega = sqrt(9.8 * k);               // 深水色散关系 ω² = g·k
            float2 D = normalize(wave.xy);
            float theta = k * dot(D, x0) - omega * t;
            float a = steep / k;                       // 振幅：陡度 = k·a，k·a = 1 时波峰恰好成尖角
            float s, c;
            sincos(theta, s, c);
            float h = _Horizontal;                     // 0 = 退化为普通正弦波（只有竖直位移）

            // 位移：水平方向 D·a·cosθ，竖直方向 a·sinθ
            float3 offset = float3(D.x * a * c * h, a * s, D.y * a * c * h);

            // 偏导数（对 x0.x、x0.z 求导，注意 ∂θ/∂x = k·D.x）
            dPdx += float3(-D.x * D.x * steep * s * h, D.x * steep * c, -D.x * D.y * steep * s * h);
            dPdz += float3(-D.x * D.y * steep * s * h, D.y * steep * c, -D.y * D.y * steep * s * h);
            return offset;
        }
        //#endregion

        //#region deform
        void Deform(inout VAAttributes v)
        {
            float3 positionWS = TransformObjectToWorld(v.positionOS.xyz);
            float2 x0 = positionWS.xz;
            float t = _Time.y + _Phase;
            float3 dPdx = float3(1, 0, 0), dPdz = float3(0, 0, 1);   // 平面本身的偏导数
            float3 offset = GerstnerWave(_WaveA, x0, t, dPdx, dPdz)
                          + GerstnerWave(_WaveB, x0, t, dPdx, dPdz)
                          + GerstnerWave(_WaveC, x0, t, dPdx, dPdz)
                          + GerstnerWave(_WaveD, x0, t, dPdx, dPdz);
            positionWS += offset;

            // 法线 = ∂P/∂z × ∂P/∂x（Unity 左手系里这个顺序朝上）
            float3 normalWS = normalize(cross(dPdz, dPdx));
            // 雅可比行列式：水平面被“挤压”的程度。< 1 表示表面被压缩，接近 0 时波峰要翻卷，正是起泡沫的地方
            float jacobian = dPdx.x * dPdz.z - dPdx.z * dPdz.x;

            v.positionOS.xyz = TransformWorldToObject(positionWS);
            v.normalOS = TransformWorldToObjectNormal(normalWS);
            v.uv2 = float4(jacobian, offset.y, 0, 0);
        }
        //#endregion

        #include "Assets/Cookbook/Ch17/VertexAnimPasses.hlsl"
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            HLSLPROGRAM
            #pragma vertex VAForwardVert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH

            //#region frag
            half4 frag(VAVaryings i) : SV_Target
            {
                float3 N = normalize(i.normalWS);
                float3 V = GetWorldSpaceNormalizeViewDir(i.positionWS);
                Light L = GetMainLight(TransformWorldToShadowCoord(i.positionWS));

                // 水体颜色：越高（波峰）越浅，模拟光在薄水层里的透射
                half crest = saturate(i.extra.y * 0.8h + 0.5h);
                half3 water = lerp(_DeepColor.rgb, _ShallowColor.rgb, crest * crest);
                half3 col = water * (saturate(dot(N, L.direction)) * 0.5h + 0.5h) * (L.color * L.shadowAttenuation * 0.6h + SampleSH(N));

                // 菲涅尔反射天空（水的 F0 约 0.02）
                half fresnel = 0.02h + 0.98h * pow(1.0h - saturate(dot(N, V)), 5.0h);
                half3 refl = GlossyEnvironmentReflection(reflect(-V, N), 0.05h, 1.0h);
                col = lerp(col, refl, fresnel);

                // 太阳高光
                float3 H = normalize(L.direction + V);
                col += pow(saturate(dot(N, H)), 400.0h) * 6.0h * L.color * L.shadowAttenuation;

                // 泡沫：雅可比行列式越小（越被压缩）泡沫越多
                half foam = saturate((_FoamThreshold - i.extra.x) / max(_FoamThreshold, 1e-3) * 2.0h);
                col = lerp(col, _FoamColor.rgb * (SampleSH(N) + L.color * 0.6h), foam);
                return half4(col, 1);
            }
            //#endregion
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0
            HLSLPROGRAM
            #pragma vertex VAShadowVert
            #pragma fragment VANullFrag
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            HLSLPROGRAM
            #pragma vertex VADepthVert
            #pragma fragment VANullFrag
            ENDHLSL
        }
    }
}
