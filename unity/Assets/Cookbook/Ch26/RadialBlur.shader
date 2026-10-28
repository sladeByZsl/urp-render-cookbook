// 案例 26.5：径向模糊——沿“像素 → 中心”的方向多次采样求平均。
Shader "Cookbook/Ch26/RadialBlur"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        ZTest Always ZWrite Off Cull Off
        Pass
        {
            Name "RadialBlur"
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float4 _RadialParams;   // xy 中心, z 强度, w 采样数
            float  _ClearRadius;

            float InterleavedGradientNoise(float2 pixel)
            {
                return frac(52.9829189 * frac(dot(pixel, float2(0.06711056, 0.00583715))));
            }

            //#region frag
            half4 Frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                float2 uv = input.texcoord;
                float2 center = _RadialParams.xy;
                float2 dir = uv - center;                       // 指向外侧，长度 = 到中心的距离

                // 中心一圈保持清晰：按宽高比修正成正圆后再算距离
                float aspect = _ScreenParams.x / _ScreenParams.y;
                float dist = length(dir * float2(aspect, 1.0));
                float amount = _RadialParams.z * smoothstep(_ClearRadius, _ClearRadius + 0.25, dist);

                int count = (int)_RadialParams.w;
                // 每个像素的起点加一点抖动，把“分层的重影”变成细噪点
                float jitter = InterleavedGradientNoise(uv * _ScreenParams.xy);
                half3 sum = 0;
                [loop] for (int i = 0; i < count; i++)
                {
                    float t = (i + jitter) / count;             // 0..1
                    float2 s = uv - dir * amount * 0.3 * t;     // 向中心方向收缩
                    sum += SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, s).rgb;
                }
                return half4(sum / count, 1.0);
            }
            //#endregion
            ENDHLSL
        }
    }
}
