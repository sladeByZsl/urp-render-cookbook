// Gooch 冷暖着色：用“冷→暖”的色相变化代替“暗→亮”的明度变化来表达朝向，
// 暗部不再是死黑，形体在技术插图里依旧清楚。附带白色高光与背面外扩描边。
Shader "Cookbook/Ch15/Gooch"
{
    Properties
    {
        _BaseColor ("Base Color (k_d)", Color) = (0.8, 0.25, 0.2, 1)
        _CoolColor ("Cool Color (b)", Color) = (0.0, 0.05, 0.45, 1)
        _WarmColor ("Warm Color (y)", Color) = (0.45, 0.4, 0.0, 1)
        _Alpha ("Alpha (cool mix)", Range(0, 1)) = 0.25
        _Beta ("Beta (warm mix)", Range(0, 1)) = 0.55
        _SpecPower ("Specular Power", Range(4, 256)) = 48
        _SpecStrength ("Specular Strength", Range(0, 1)) = 0.8
        _ShadowCool ("Shadow pushes to cool", Range(0, 1)) = 0.6
        _OutlineWidth ("Outline Width", Range(0, 0.05)) = 0.012
        _OutlineColor ("Outline Color", Color) = (0.05, 0.05, 0.08, 1)
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        CBUFFER_START(UnityPerMaterial)
            half4 _BaseColor, _CoolColor, _WarmColor, _OutlineColor;
            half  _Alpha, _Beta, _SpecPower, _SpecStrength, _ShadowCool;
            float _OutlineWidth;
        CBUFFER_END
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            HLSLPROGRAM
            #pragma vertex NprVert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #pragma multi_compile_fog
            #include "Assets/Cookbook/Ch15/NPRCommon.hlsl"

            //#region frag
            half4 frag(NprVaryings i) : SV_Target
            {
                float3 N = normalize(i.normalWS);
                float3 V = GetWorldSpaceNormalizeViewDir(i.positionWS);
                NprLight L = GetNprLight(i.positionWS, N);

                // 1) 冷暖两端：纯冷/暖色 + 一部分物体本色
                half3 kCool = _CoolColor.rgb + _Alpha * _BaseColor.rgb;
                half3 kWarm = _WarmColor.rgb + _Beta  * _BaseColor.rgb;

                // 2) 用 (1 + N·L) / 2 在两端之间插值：背光面不是“没有光”，而是“偏冷”
                half t = (1.0h + L.ndotl) * 0.5h;
                // 落在投影里的部分往冷端推一些（原始 Gooch 模型没有阴影，这是工程上的补充）
                t *= lerp(1.0h - _ShadowCool, 1.0h, L.shadow);
                half3 col = lerp(kCool, kWarm, t);

                // 3) 白色高光：Blinn-Phong，只在受光面出现
                float3 H = normalize(L.direction + V);
                half spec = pow(saturate(dot(N, H)), _SpecPower) * _SpecStrength * L.shadow * step(0, L.ndotl);
                col += spec;

                col = MixFog(col, i.fogFactor);
                return half4(col, 1);
            }
            //#endregion
            ENDHLSL
        }

        // 背面外扩描边（第 14 章讲过的方法，这里只作为技术插图的黑色轮廓线）
        Pass
        {
            Name "Outline"
            Tags { "LightMode"="SRPDefaultUnlit" }
            Cull Front
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            struct A { float4 positionOS : POSITION; float3 normalOS : NORMAL; };
            float4 vert(A v) : SV_POSITION
            {
                float4 positionCS = TransformObjectToHClip(v.positionOS.xyz);
                float3 normalCS = mul((float3x3)UNITY_MATRIX_VP, TransformObjectToWorldNormal(v.normalOS));
                // 在裁剪空间沿法线外扩，乘 w 抵消透视除法，使线宽与距离无关
                float2 offset = normalize(normalCS.xy) * _OutlineWidth * positionCS.w;
                offset.x *= _ScreenParams.y / _ScreenParams.x;   // 纠正宽高比
                positionCS.xy += offset;
                return positionCS;
            }
            half4 frag() : SV_Target { return _OutlineColor; }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0
            HLSLPROGRAM
            #pragma vertex NprShadowVert
            #pragma fragment NprNullFrag
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Assets/Cookbook/Ch15/NPRCommon.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            HLSLPROGRAM
            #pragma vertex NprDepthVert
            #pragma fragment NprNullFrag
            #include "Assets/Cookbook/Ch15/NPRCommon.hlsl"
            ENDHLSL
        }
    }
}
