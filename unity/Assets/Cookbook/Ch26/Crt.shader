// 案例 26.8：CRT。所有效果都在一个 Pass 里按“几何 → 采样 → 逐像素调制”的顺序完成。
Shader "Cookbook/Ch26/Crt"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        ZTest Always ZWrite Off Cull Off
        Pass
        {
            Name "CRT"
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float4 _CrtParams0;   // x 强度, y 弯曲, z 行数, w 扫描线强度
            float4 _CrtParams1;   // x 栅格强度, y 闪烁

            //#region frag
            half4 Frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                float2 uv0 = input.texcoord;

                // 1) 弯曲：把 [-1,1] 坐标按到中心距离的平方向外推，模拟鼓起的玻璃屏
                float2 p = uv0 * 2.0 - 1.0;
                p *= 1.0 + _CrtParams0.y * dot(p, p) * 0.5;
                float2 uv = p * 0.5 + 0.5;

                // 屏幕外（被弯曲推出去的部分）是黑色边框；用 SDF 圆角矩形做柔和的边
                float2 q = abs(p) - (1.0 - 0.06);
                float box = length(max(q, 0.0)) - 0.06;
                half inside = 1.0 - smoothstep(-0.005, 0.005, box);

                // 2) 采样：三个通道错开约 1 像素，像电子枪没对准
                float2 px = float2(1.0 / _ScreenParams.x, 0);
                half3 c;
                c.r = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + px).r;
                c.g = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv).g;
                c.b = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv - px).b;

                // 3) 扫描线：每行中间亮、行间暗；用弯曲后的 uv，扫描线也跟着弯
                float row = uv.y * _CrtParams0.z;
                half scan = 0.5 + 0.5 * cos(row * TWO_PI);
                c *= lerp(1.0, 0.35 + 0.65 * scan, _CrtParams0.w);

                // 4) 荧光粉栅格：屏幕像素 x 坐标每 3 列一组，分别偏 R、G、B
                int col = (int)fmod(input.texcoord.x * _ScreenParams.x, 3.0);
                half3 mask = col == 0 ? half3(1, 0.4, 0.4) : (col == 1 ? half3(0.4, 1, 0.4) : half3(0.4, 0.4, 1));
                c *= lerp(1.0, mask * 1.6, _CrtParams1.x);

                // 5) 边缘暗角 + 闪烁（_Time 驱动，截图时 _Time≈0）
                half vignette = saturate(1.0 - dot(p, p) * 0.25);
                half flick = 1.0 - _CrtParams1.y * (0.5 + 0.5 * sin(_Time.y * 110.0));
                c *= vignette * flick * inside;

                // 6) 总强度：和原图插值，方便做“开机/切换”过渡
                half3 original = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv0).rgb;
                return half4(lerp(original, c, _CrtParams0.x), 1.0);
            }
            //#endregion
            ENDHLSL
        }
    }
}
