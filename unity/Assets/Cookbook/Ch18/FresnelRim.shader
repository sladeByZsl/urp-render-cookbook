// 案例 18.4：菲涅尔边缘光（Rim Light）。不透明基础光照 + 叠加一圈轮廓亮边。
Shader "Cookbook/Ch18/FresnelRim"
{
    Properties
    {
        [MainColor] _BaseColor ("Base Color", Color) = (0.25,0.27,0.3,1)
        _Smoothness ("Smoothness", Range(0,1)) = 0.5
        [HDR] _RimColor ("Rim Color", Color) = (0.3,0.8,2,1)
        _RimPower ("Rim Power", Range(0.5,16)) = 3
        _RimIntensity ("Rim Intensity", Range(0,4)) = 1
        _RimLightMask ("Mask By Light (0=none 1=back side only)", Range(0,1)) = 0
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" "RenderPipeline"="UniversalPipeline" }

        // HLSLINCLUDE 里的代码会插到本 SubShader 每个 Pass 的最前面：CBUFFER 写一次，所有 Pass 一致
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        CBUFFER_START(UnityPerMaterial)
            half4 _BaseColor;
            half  _Smoothness;
            half4 _RimColor;
            half  _RimPower;
            half  _RimIntensity;
            half  _RimLightMask;
        CBUFFER_END
        ENDHLSL

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
            #include "Assets/Cookbook/Ch18/Ch18Common.hlsl"

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; };
            struct Varyings  { float4 positionCS : SV_POSITION; float3 positionWS : TEXCOORD0; half3 normalWS : TEXCOORD1; };

            Varyings vert(Attributes v)
            {
                Varyings o;
                o.positionWS = TransformObjectToWorld(v.positionOS.xyz);
                o.positionCS = TransformWorldToHClip(o.positionWS);
                o.normalWS = TransformObjectToWorldNormal(v.normalOS);
                return o;
            }

            //#region frag
            half4 frag(Varyings i) : SV_Target
            {
                half3 normalWS = normalize(i.normalWS);
                half3 viewWS = GetWorldSpaceNormalizeViewDir(i.positionWS);
                half3 color = SimpleLighting(_BaseColor.rgb, i.positionWS, normalWS, _Smoothness);

                half rim = FresnelRim(normalWS, viewWS, _RimPower);
                // 可选：只在背光一侧显示亮边（经典的“轮廓光”打法），受光侧交给正常光照
                half NdotL = dot(normalWS, GetMainLight().direction);
                half lightMask = lerp(1.0h, smoothstep(0.2h, -0.4h, NdotL), _RimLightMask);
                color += _RimColor.rgb * rim * _RimIntensity * lightMask;
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
            #pragma vertex ShadowVert
            #pragma fragment ShadowFrag
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Assets/Cookbook/Ch18/Ch18ShadowPass.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            HLSLPROGRAM
            #pragma vertex DepthVert
            #pragma fragment DepthFrag
            #include "Assets/Cookbook/Ch18/Ch18ShadowPass.hlsl"
            ENDHLSL
        }
    }
}
