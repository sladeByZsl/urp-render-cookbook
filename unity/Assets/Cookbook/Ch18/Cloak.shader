// 案例 18.8：扭曲隐身（光学迷彩）。采样 _CameraOpaqueTexture，按法线把屏幕 UV 推开一点，
// 物体就像一块“透明的玻璃”把身后的画面弯折了。URP Asset 需开启 Opaque Texture。
Shader "Cookbook/Ch18/Cloak"
{
    Properties
    {
        _Distortion ("Distortion (screen UV)", Range(0,0.15)) = 0.04
        _NoiseMap ("Ripple Noise", 2D) = "gray" {}
        _NoiseDistortion ("Noise Distortion", Range(0,0.05)) = 0.01
        _Tint ("Tint", Color) = (0.9,0.95,1,1)
        [HDR] _RimColor ("Rim Color", Color) = (0.4,0.9,1.4,1)
        _RimPower ("Rim Power", Range(0.5,8)) = 4
        _Reveal ("Reveal (0=invisible 1=visible)", Range(0,1)) = 0
        _BaseColor ("Visible Base Color", Color) = (0.7,0.3,0.2,1)
        [Toggle] _AutoPlay ("Auto Play (_Time)", Float) = 0
        _Phase ("Phase (seconds)", Float) = 0
    }

    SubShader
    {
        // 透明队列：画它的时候，不透明物体和天空已经拷贝进 _CameraOpaqueTexture 了
        Tags { "RenderType"="Transparent" "Queue"="Transparent" "RenderPipeline"="UniversalPipeline" }

        Pass
        {
            Name "Cloak"
            Tags { "LightMode"="UniversalForward" }
            ZWrite On           // 写深度：隐身物体自己的前后遮挡仍然正确（它不是半透明混合，而是整块替换）
            Blend Off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #pragma multi_compile _ _FORWARD_PLUS
            #include "Assets/Cookbook/Ch18/Ch18Common.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"

            TEXTURE2D(_NoiseMap); SAMPLER(sampler_NoiseMap);

            CBUFFER_START(UnityPerMaterial)
                half   _Distortion;
                float4 _NoiseMap_ST;
                half   _NoiseDistortion;
                half4  _Tint;
                half4  _RimColor;
                half   _RimPower;
                half   _Reveal;
                half4  _BaseColor;
                half   _AutoPlay;
                float  _Phase;
            CBUFFER_END

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; float2 uv : TEXCOORD0; };
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                half3  normalWS   : TEXCOORD1;
                float2 uv         : TEXCOORD2;
            };

            Varyings vert(Attributes v)
            {
                Varyings o;
                o.positionWS = TransformObjectToWorld(v.positionOS.xyz);
                o.positionCS = TransformWorldToHClip(o.positionWS);
                o.normalWS = TransformObjectToWorldNormal(v.normalOS);
                o.uv = TRANSFORM_TEX(v.uv, _NoiseMap);
                return o;
            }

            //#region frag
            half4 frag(Varyings i) : SV_Target
            {
                float t = _AutoPlay > 0.5 ? _Time.y : _Phase;
                half3 normalWS = normalize(i.normalWS);
                half3 viewWS = GetWorldSpaceNormalizeViewDir(i.positionWS);
                float2 screenUV = GetNormalizedScreenSpaceUV(i.positionCS);

                // 法线转到观察空间，取 xy 作为屏幕上的“推开方向”：轮廓处法线几乎平行屏幕，推得最远
                half3 normalVS = TransformWorldToViewDir(normalWS);
                float2 offset = normalVS.xy * _Distortion;
                // 再叠一层流动噪声，让隐身体表面有“热浪”一样的抖动
                half2 n = SAMPLE_TEXTURE2D(_NoiseMap, sampler_NoiseMap, i.uv + float2(0, t * 0.2)).rg - 0.5h;
                offset += n * _NoiseDistortion;
                // 观察空间 x 向右、y 向上，与 GetNormalizedScreenSpaceUV 得到的 UV 方向一致（平台翻转已由它处理）
                half3 behind = SampleSceneColor(screenUV + offset) * _Tint.rgb;

                half rim = FresnelRim(normalWS, viewWS, _RimPower);
                half3 cloak = behind + _RimColor.rgb * rim;

                // 现形：在隐身和正常着色之间插值（实际项目可以叠一个溶解，见案例 18.1）
                half3 visible = SimpleLighting(_BaseColor.rgb, i.positionWS, normalWS, 0.4h);
                return half4(lerp(cloak, visible, _Reveal), 1);
            }
            //#endregion
            ENDHLSL
        }
    }
}
