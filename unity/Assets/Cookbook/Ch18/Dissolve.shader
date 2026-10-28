// 案例 18.1~18.3：溶解。噪声 clip + 边缘发光 + 三种溶解形状（噪声 / 方向 / 球形）。
Shader "Cookbook/Ch18/Dissolve"
{
    Properties
    {
        [MainTexture] _BaseMap ("Base Map", 2D) = "white" {}
        [MainColor] _BaseColor ("Base Color", Color) = (1,1,1,1)
        _Smoothness ("Smoothness", Range(0,1)) = 0.4
        [Header(Dissolve)]
        [NoScaleOffset] _NoiseMap ("Noise (R)", 2D) = "gray" {}
        _NoiseMap_ST ("Noise Tiling/Offset", Vector) = (1,1,0,0)
        _Progress ("Progress", Range(0,1)) = 0.3
        [Toggle] _AutoPlay ("Auto Play (_Time)", Float) = 0
        [KeywordEnum(Noise, Direction, Sphere)] _Mode ("Mode", Float) = 0
        _NoiseStrength ("Noise Strength (Dir/Sphere)", Range(0,1)) = 0.25
        _DissolveDir ("Direction (Object)", Vector) = (0,1,0,0)
        _DirRange ("Direction Range (min,max)", Vector) = (-0.5,0.5,0,0)
        _SphereCenter ("Sphere Center(xyz) MaxRadius(w)", Vector) = (0,0,0,2)
        [Header(Edge)]
        _EdgeWidth ("Edge Width", Range(0,0.3)) = 0.08
        [HDR] _EdgeColor ("Edge Color", Color) = (4,1.6,0.4,1)
        [Toggle] _UseRamp ("Use Ramp", Float) = 1
        [NoScaleOffset] _EdgeRamp ("Edge Ramp", 2D) = "white" {}
        [Enum(UnityEngine.Rendering.CullMode)] _Cull ("Cull", Float) = 0
    }

    SubShader
    {
        // 溶解本质是 Alpha Test：用 AlphaTest 队列，让 Early-Z 友好的不透明物体先画
        Tags { "RenderType"="TransparentCutout" "Queue"="AlphaTest" "RenderPipeline"="UniversalPipeline" }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }
            Cull [_Cull]

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma shader_feature_local _MODE_NOISE _MODE_DIRECTION _MODE_SPHERE
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #pragma multi_compile _ _FORWARD_PLUS
            #pragma multi_compile_fog

            #include "Assets/Cookbook/Ch18/DissolveCore.hlsl"
            #include "Assets/Cookbook/Ch18/Ch18Common.hlsl"

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
                float3 positionOS : TEXCOORD2;
                half3  normalWS   : TEXCOORD3;
                half   fogFactor  : TEXCOORD4;
            };

            Varyings vert(Attributes v)
            {
                Varyings o;
                VertexPositionInputs p = GetVertexPositionInputs(v.positionOS.xyz);
                o.positionCS = p.positionCS;
                o.positionWS = p.positionWS;
                o.positionOS = v.positionOS.xyz;
                o.normalWS = TransformObjectToWorldNormal(v.normalOS);
                o.uv = v.uv;
                o.fogFactor = ComputeFogFactor(p.positionCS.z);
                return o;
            }

            //#region frag
            half4 frag(Varyings i, FRONT_FACE_TYPE face : FRONT_FACE_SEMANTIC) : SV_Target
            {
                half edge;
                DissolveClip(DissolveValue(i.uv, i.positionOS, i.positionWS), edge);

                half3 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv * _BaseMap_ST.xy + _BaseMap_ST.zw).rgb * _BaseColor.rgb;
                // 双面渲染时，背面（物体内壁）把法线翻过来，再压暗一点，看起来像“空心的内部”
                half3 normalWS = normalize(i.normalWS) * IS_FRONT_VFACE(face, 1.0h, -1.0h);
                albedo *= IS_FRONT_VFACE(face, 1.0h, 0.35h);

                // 前沿附近先“烧焦”变暗，再在最前沿发光
                albedo *= 1.0h - 0.85h * smoothstep(0.0h, 0.6h, edge);
                half3 color = SimpleLighting(albedo, i.positionWS, normalWS, _Smoothness);

                half3 glow = _EdgeColor.rgb;
                if (_UseRamp > 0.5)
                    glow *= SAMPLE_TEXTURE2D(_EdgeRamp, sampler_EdgeRamp, float2(edge, 0.5)).rgb;
                // edge^2：让发光集中在最前沿，向内快速衰减
                color += glow * edge * edge;

                color = MixFog(color, i.fogFactor);
                return half4(color, 1);
            }
            //#endregion
            ENDHLSL
        }

        //#region shadow
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0
            Cull [_Cull]

            HLSLPROGRAM
            #pragma vertex vertShadow
            #pragma fragment fragClip
            #pragma shader_feature_local _MODE_NOISE _MODE_DIRECTION _MODE_SPHERE
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Assets/Cookbook/Ch18/DissolveCore.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            float3 _LightDirection;   // 由 URP 的 ShadowUtils 在画阴影前设置
            float3 _LightPosition;

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; float2 uv : TEXCOORD0; };
            struct Varyings  { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; float3 positionOS : TEXCOORD1; float3 positionWS : TEXCOORD2; };

            Varyings vertShadow(Attributes v)
            {
                Varyings o;
                float3 positionWS = TransformObjectToWorld(v.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(v.normalOS);
            #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                float3 lightDirWS = normalize(_LightPosition - positionWS);
            #else
                float3 lightDirWS = _LightDirection;
            #endif
                o.positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirWS));
            #if UNITY_REVERSED_Z
                o.positionCS.z = min(o.positionCS.z, UNITY_NEAR_CLIP_VALUE);
            #else
                o.positionCS.z = max(o.positionCS.z, UNITY_NEAR_CLIP_VALUE);
            #endif
                o.uv = v.uv; o.positionOS = v.positionOS.xyz; o.positionWS = positionWS;
                return o;
            }

            half4 fragClip(Varyings i) : SV_Target
            {
                half edge;
                DissolveClip(DissolveValue(i.uv, i.positionOS, i.positionWS), edge);
                return 0;
            }
            ENDHLSL
        }
        //#endregion

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            Cull [_Cull]

            HLSLPROGRAM
            #pragma vertex vertDepth
            #pragma fragment fragClip
            #pragma shader_feature_local _MODE_NOISE _MODE_DIRECTION _MODE_SPHERE
            #include "Assets/Cookbook/Ch18/DissolveCore.hlsl"

            struct Attributes { float4 positionOS : POSITION; float2 uv : TEXCOORD0; };
            struct Varyings  { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; float3 positionOS : TEXCOORD1; float3 positionWS : TEXCOORD2; };

            Varyings vertDepth(Attributes v)
            {
                Varyings o;
                o.positionWS = TransformObjectToWorld(v.positionOS.xyz);
                o.positionCS = TransformWorldToHClip(o.positionWS);
                o.uv = v.uv; o.positionOS = v.positionOS.xyz;
                return o;
            }

            half4 fragClip(Varyings i) : SV_Target
            {
                half edge;
                DissolveClip(DissolveValue(i.uv, i.positionOS, i.positionWS), edge);
                return i.positionCS.z;
            }
            ENDHLSL
        }
    }
}
