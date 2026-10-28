// 案例 18.9：冰冻 / 结晶覆盖。世界空间“自上而下”覆盖一层冰：加厚、冰裂纹、高光滑度、冷色边缘与闪点。
Shader "Cookbook/Ch18/Frozen"
{
    Properties
    {
        [MainTexture] _BaseMap ("Base Map", 2D) = "white" {}
        [MainColor] _BaseColor ("Base Color", Color) = (1,1,1,1)
        _Smoothness ("Base Smoothness", Range(0,1)) = 0.3
        _Freeze ("Freeze", Range(0,1)) = 0.5
        _IceColor ("Ice Color", Color) = (0.78,0.9,1,1)
        _IceDeepColor ("Ice Deep Color", Color) = (0.25,0.5,0.75,1)
        [NoScaleOffset] _IceNoise ("Ice Noise", 2D) = "gray" {}
        _IceNoiseScale ("Ice Noise Scale", Float) = 0.6
        [NoScaleOffset] _CrackMap ("Crack (Worley)", 2D) = "black" {}
        _CrackScale ("Crack Scale", Float) = 1.2
        _CrackStrength ("Crack Strength", Range(0,2)) = 0.8
        _Thickness ("Thickness (m)", Range(0,0.1)) = 0.025
        [HDR] _IceRimColor ("Ice Rim Color", Color) = (0.6,0.9,1.5,1)
        _SparkleStrength ("Sparkle", Range(0,20)) = 6
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" "RenderPipeline"="UniversalPipeline" }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #pragma multi_compile _ _FORWARD_PLUS
            #include "Assets/Cookbook/Ch18/FrozenCore.hlsl"
            #include "Assets/Cookbook/Ch18/Ch18Common.hlsl"

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; float2 uv : TEXCOORD0; };
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                half3  normalWS   : TEXCOORD1;
                float2 uv         : TEXCOORD2;
                float3 restWS     : TEXCOORD3;   // 加厚之前的位置，用来采样噪声，避免纹理随厚度“游动”
            };

            Varyings vert(Attributes v)
            {
                Varyings o;
                float3 positionWS = TransformObjectToWorld(v.positionOS.xyz);
                half3 normalWS = TransformObjectToWorldNormal(v.normalOS);
                o.restWS = positionWS;
                o.positionWS = ThickenIce(positionWS, normalWS);
                o.positionCS = TransformWorldToHClip(o.positionWS);
                o.normalWS = normalWS;
                o.uv = TRANSFORM_TEX(v.uv, _BaseMap);
                return o;
            }

            //#region frag
            half4 frag(Varyings i) : SV_Target
            {
                half3 normalWS = normalize(i.normalWS);
                half3 viewWS = GetWorldSpaceNormalizeViewDir(i.positionWS);
                half mask = FrostMask(i.restWS, normalWS);

                half3 baseAlbedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv).rgb * _BaseColor.rgb;

                // 冰的颜色：噪声在浅色与深色之间变化，Worley 的细胞边界做成白色裂纹
                half n = TriplanarNoise(TEXTURE2D_ARGS(_IceNoise, sampler_IceNoise), i.restWS, normalWS, _IceNoiseScale * 3.0);
                half cell = TriplanarNoise(TEXTURE2D_ARGS(_CrackMap, sampler_CrackMap), i.restWS, normalWS, _CrackScale);
                half crack = smoothstep(0.55h, 0.8h, cell) * _CrackStrength;
                half3 ice = lerp(_IceDeepColor.rgb, _IceColor.rgb, saturate(n * 1.2h + crack));
                // 冰层很薄的地方（遮罩边缘）透出一点底色
                half3 albedo = lerp(baseAlbedo, ice, mask * (0.75h + 0.25h * mask));
                half smooth = lerp(_Smoothness, 0.9h, mask);

                half3 color = SimpleLighting(albedo, i.positionWS, normalWS, smooth);

                // 冷色菲涅尔：冰面边缘泛蓝白，模拟光在冰层里散射后从边缘透出来
                half rim = FresnelRim(normalWS, viewWS, 3.0h);
                color += _IceRimColor.rgb * rim * mask;

                // 闪点：极高频哈希，只保留最亮的极少数点；乘上视角相关的项，转动相机时会“闪”
                float3 sp = floor(i.restWS * 160.0);
                half sparkle = step(0.997h, Hash21(sp.xz + sp.y * 17.0));
                half3 halfDir = SafeNormalize(GetMainLight().direction + viewWS);
                sparkle *= pow(saturate(dot(normalWS, halfDir)), 8.0h);
                color += sparkle * _SparkleStrength * mask * GetMainLight().color;
                return half4(color, 1);
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
            #pragma vertex vertShadow
            #pragma fragment fragShadow
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Assets/Cookbook/Ch18/FrozenCore.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
            float3 _LightDirection;
            float3 _LightPosition;
            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; };
            float4 vertShadow(Attributes v) : SV_POSITION
            {
                float3 positionWS = TransformObjectToWorld(v.positionOS.xyz);
                half3 normalWS = TransformObjectToWorldNormal(v.normalOS);
                positionWS = ThickenIce(positionWS, normalWS);
            #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                float3 lightDirWS = normalize(_LightPosition - positionWS);
            #else
                float3 lightDirWS = _LightDirection;
            #endif
                float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirWS));
            #if UNITY_REVERSED_Z
                positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
            #else
                positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
            #endif
                return positionCS;
            }
            half4 fragShadow() : SV_Target { return 0; }
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            HLSLPROGRAM
            #pragma vertex vertDepth
            #pragma fragment fragDepth
            #include "Assets/Cookbook/Ch18/FrozenCore.hlsl"
            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; };
            float4 vertDepth(Attributes v) : SV_POSITION
            {
                float3 positionWS = TransformObjectToWorld(v.positionOS.xyz);
                return TransformWorldToHClip(ThickenIce(positionWS, TransformObjectToWorldNormal(v.normalOS)));
            }
            half4 fragDepth(float4 positionCS : SV_POSITION) : SV_Target { return positionCS.z; }
            ENDHLSL
        }
    }
}
