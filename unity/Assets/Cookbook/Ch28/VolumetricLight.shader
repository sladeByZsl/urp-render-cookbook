// 案例 28.5：体积光（主光方向光的光束 / God Rays）。
// Pass 0：半分辨率光线步进，逐步采样主光阴影图；Pass 1/2：可分离模糊；Pass 3：合成到相机颜色；Pass 4：只看散射项
Shader "Cookbook/Ch28/VolumetricLight"
{
    Properties
    {
        _Density ("Density (1/m)", Float) = 0.06
        _Anisotropy ("HG Anisotropy g", Range(-0.9, 0.95)) = 0.6
        _MaxDistance ("Max March Distance", Float) = 30
        _Steps ("Steps", Range(4, 64)) = 24
        _Intensity ("Intensity", Float) = 1
        [Toggle] _Jitter ("Jitter Start", Float) = 1
        _Tint ("Tint", Color) = (1, 0.92, 0.8, 1)
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        ZWrite Off ZTest Always Cull Off Blend Off

        HLSLINCLUDE
        #include "Assets/Cookbook/Ch28/ScreenSpaceCommon.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Random.hlsl"

        CBUFFER_START(UnityPerMaterial)
            float _Density, _Anisotropy, _MaxDistance, _Steps, _Intensity, _Jitter;
            half4 _Tint;
        CBUFFER_END
        float4 _VolTexelSize;           // 体积纹理的 (1/w, 1/h, w, h)
        TEXTURE2D_X(_VolumetricResult); // 合成时读取（r = 散射，g = 透射率）

        half4 Blur9(float2 uv, float2 dir)
        {
            static const float w[5] = { 0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216 };
            half4 sum = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv) * w[0];
            for (int i = 1; i < 5; i++)
            {
                sum += SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + dir * i) * w[i];
                sum += SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv - dir * i) * w[i];
            }
            return sum;
        }
        ENDHLSL

        Pass
        {
            Name "RayMarch"
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment FragMarch
            //#region keywords
            // 主光阴影的关键字由 URP 在渲染阴影图后全局开启；全屏 Pass 只要声明同样的变体即可。
            // 不需要 _MAIN_LIGHT_SHADOWS_SCREEN：屏幕空间阴影只有“表面”上的结果，体积里的点用不上。
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            // Shadows.hlsl 用到 CommonMaterial.hlsl 里的 LerpWhiteTo，但自己没 include（Lit 走 Lighting.hlsl 时会间接带上）
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/RealtimeLights.hlsl"
            //#endregion

            //#region march
            // Henyey-Greenstein 相位函数：g>0 时向前散射为主，迎着光看最亮
            float PhaseHG(float cosTheta, float g)
            {
                float g2 = g * g;
                return INV_FOUR_PI * (1 - g2) / pow(max(1 + g2 - 2 * g * cosTheta, 1e-4), 1.5);
            }

            half4 FragMarch(Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                float2 uv = input.texcoord;
                float depth = SampleDeviceDepth(uv);
                float3 endWS = IsSkyDepth(depth)
                    ? ComputeWorldSpacePosition(uv, UNITY_RAW_FAR_CLIP_VALUE, UNITY_MATRIX_I_VP)
                    : ReconstructPositionWS(uv, depth);

                float3 rayWS = endWS - _WorldSpaceCameraPos;
                float rayLength = min(length(rayWS), _MaxDistance);
                float3 dir = rayWS / max(length(rayWS), 1e-4);

                Light mainLight = GetMainLight();
                float phase = PhaseHG(dot(dir, mainLight.direction), _Anisotropy);

                int steps = (int)_Steps;
                float stepLength = rayLength / steps;
                // 抖动起点：把“条带”换成高频噪声，再交给模糊去掉
                float jitter = _Jitter > 0.5 ? InterleavedGradientNoise(input.positionCS.xy, 0) : 0.5;

                float scatter = 0;
                float transmittance = 1;
                float stepT = exp(-_Density * stepLength);    // 每步的透射率（均匀介质）
                for (int i = 0; i < steps; i++)
                {
                    float t = (i + jitter) * stepLength;
                    float3 p = _WorldSpaceCameraPos + dir * t;
                    // 关键两行：世界坐标 → 阴影坐标（自动选级联）→ 比较阴影图
                    float4 shadowCoord = TransformWorldToShadowCoord(p);
                    float visibility = MainLightRealtimeShadow(shadowCoord);
                    // 这一小段介质散射到相机方向的光，再乘上它到相机之间的透射率
                    scatter += visibility * transmittance * (1 - stepT);
                    transmittance *= stepT;
                }
                scatter *= phase * _Intensity * FOUR_PI;  // ×4π 让 g=0 时的强度约为 1，便于调参
                return half4(scatter, transmittance, 0, 1);
            }
            //#endregion
            ENDHLSL
        }

        Pass
        {
            Name "BlurH"
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            half4 Frag(Varyings input) : SV_Target { return Blur9(input.texcoord, float2(_VolTexelSize.x, 0)); }
            ENDHLSL
        }
        Pass
        {
            Name "BlurV"
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            half4 Frag(Varyings input) : SV_Target { return Blur9(input.texcoord, float2(0, _VolTexelSize.y)); }
            ENDHLSL
        }
        Pass
        {
            Name "Composite"
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            // Shadows.hlsl 用到 CommonMaterial.hlsl 里的 LerpWhiteTo，但自己没 include（Lit 走 Lighting.hlsl 时会间接带上）
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/RealtimeLights.hlsl"
            //#region composite
            half4 Frag(Varyings input) : SV_Target
            {
                half4 color = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_PointClamp, input.texcoord);
                half2 vol = SAMPLE_TEXTURE2D_X(_VolumetricResult, sampler_LinearClamp, input.texcoord).rg;
                half3 lightColor = GetMainLight().color * _Tint.rgb;
                // 场景被介质衰减（×透射率），再加上介质散射进视线的光
                color.rgb = color.rgb * vol.g + lightColor * vol.r;
                return color;
            }
            //#endregion
            ENDHLSL
        }
        Pass
        {
            Name "ShowScatter"
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            half4 Frag(Varyings input) : SV_Target
            {
                half s = SAMPLE_TEXTURE2D_X(_VolumetricResult, sampler_LinearClamp, input.texcoord).r;
                return half4(s.xxx, 1);
            }
            ENDHLSL
        }
    }
}
