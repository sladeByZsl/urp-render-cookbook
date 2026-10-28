// 案例 6.3 接收主光源阴影：Lambert + MainLightRealtimeShadow
Shader "Cookbook/Ch06/ShadowReceive"
{
    Properties
    {
        [MainTexture] _BaseMap("Base Map", 2D) = "white" {}
        [MainColor] _BaseColor("Base Color", Color) = (0.8, 0.8, 0.8, 1)
        _AmbientStrength("Ambient Strength", Range(0, 1)) = 0.4
        [Toggle(_RECEIVE_SHADOWS_OFF)] _ReceiveShadowsOff("Receive Shadows Off", Float) = 0
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half4  _BaseColor;
            half   _AmbientStrength;
        CBUFFER_END
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            //#region keywords
            // 主光阴影：无 / 单张阴影图 / 级联 / 屏幕空间（由 URP Asset 与 Renderer 设置决定，运行时自动开关）
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            // 软阴影：_SHADOWS_SOFT 在运行时按每盏灯的质量分支；LOW/MEDIUM/HIGH 是给“必须静态分支”的平台准备的
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            // 材质级开关：不接收阴影
            #pragma shader_feature_local _RECEIVE_SHADOWS_OFF
            //#endregion

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS   : TEXCOORD2;
            };

            Varyings vert(Attributes input)
            {
                Varyings output;
                VertexPositionInputs pos = GetVertexPositionInputs(input.positionOS.xyz);
                output.positionCS = pos.positionCS;
                output.positionWS = pos.positionWS;
                output.normalWS = TransformObjectToWorldNormal(input.normalOS);
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                return output;
            }

            //#region frag
            half4 frag(Varyings input) : SV_Target
            {
                half3 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv).rgb * _BaseColor.rgb;
                half3 normalWS = normalize(input.normalWS);

                // 世界坐标 -> 阴影图坐标（xy = 阴影图 UV，z = 在光源空间里的深度）。
                // 开了级联时，这里会先按距离选出级联号，再用对应的矩阵变换
                float4 shadowCoord = TransformWorldToShadowCoord(input.positionWS);

                // 采样阴影图并与 z 比较：1 = 受光，0 = 在阴影里（软阴影时是 0~1 的过渡）
                half shadow = MainLightRealtimeShadow(shadowCoord);

                // 超出“阴影距离”的地方，阴影要平滑淡出，而不是突然消失
                shadow = lerp(shadow, 1.0, GetMainLightShadowFade(input.positionWS));

                Light mainLight = GetMainLight();
                half3 radiance = mainLight.color * mainLight.distanceAttenuation * shadow;
                half3 color = albedo * radiance * saturate(dot(normalWS, mainLight.direction));
                color += albedo * SampleSH(normalWS) * _AmbientStrength;
                return half4(color, 1);
            }
            //#endregion
            ENDHLSL
        }

        // ---- 投影与深度：见案例 6.4 与 6.8 ----
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On
            ZTest LEqual
            ColorMask 0

            HLSLPROGRAM
            #pragma vertex ShadowCasterVertex
            #pragma fragment ShadowCasterFragment
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Assets/Cookbook/Ch06/ShadowCasterPass.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On
            ColorMask R

            HLSLPROGRAM
            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment
            #include "Assets/Cookbook/Ch06/DepthOnlyPass.hlsl"
            ENDHLSL
        }
    }
}
