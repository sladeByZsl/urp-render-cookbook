// 薄片透射：树叶、耳朵、纸灯笼一类“光能从背面透过来”的薄物体。
// 透射项用 Barré-Brisebois & Bouchard (GDC 2011) 的快速近似，厚度来自程序化叶脉。
Shader "Cookbook/Ch12/Translucent"
{
    Properties
    {
        [MainColor] _BaseColor ("Leaf Color", Color) = (0.18, 0.42, 0.08, 1)
        _VeinColor ("Vein Color", Color) = (0.45, 0.6, 0.2, 1)
        [Toggle] _Transmission ("Transmission", Float) = 1
        [Toggle] _UseThickness ("Use Thickness (veins)", Float) = 1
        _TransColor ("Transmission Color", Color) = (0.75, 0.95, 0.2, 1)
        _Distortion ("Normal Distortion", Range(0, 1)) = 0.3
        _TransPower ("Power", Range(1, 16)) = 4
        _TransScale ("Scale", Range(0, 8)) = 2.5
        _TransAmbient ("Ambient Transmission", Range(0, 1)) = 0.15
        _Smoothness ("Smoothness", Range(0, 1)) = 0.55
    }

    SubShader
    {
        Tags { "RenderType"="TransparentCutout" "RenderPipeline"="UniversalPipeline" "Queue"="AlphaTest" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
        CBUFFER_START(UnityPerMaterial)
            half4 _BaseColor, _VeinColor, _TransColor;
            half  _Transmission, _UseThickness, _Distortion, _TransPower, _TransScale, _TransAmbient, _Smoothness;
        CBUFFER_END

        //#region leaf
        // 程序化叶片：UV 的 y 从叶柄(0)到叶尖(1)。返回 x=是否在叶内(符号距离)，y=叶脉强度(0~1)
        float2 LeafShape(float2 uv)
        {
            float x = uv.x - 0.5, y = uv.y;
            float halfWidth = 0.44 * pow(saturate(sin(PI * y)), 0.75) * (1.0 - 0.35 * y);
            float inside = halfWidth - abs(x);
            float mid = 1.0 - smoothstep(0.004, 0.018, abs(x));                       // 主脉
            float f = frac((y - abs(x) * 0.9) * 7.0);                                 // 斜向重复的侧脉
            float side = 1.0 - smoothstep(0.03, 0.09, min(f, 1.0 - f));
            side *= smoothstep(0.02, 0.06, abs(x)) * smoothstep(0.0, 0.1, inside);    // 侧脉，离边缘淡出
            return float2(inside, saturate(max(mid, side * 0.65)));
        }
        //#endregion
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            Cull Off   // 叶片双面可见

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex Ch12Vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #pragma multi_compile_fragment _ _LIGHT_COOKIES
            #pragma multi_compile _ _FORWARD_PLUS
            #pragma multi_compile_fog
            #pragma multi_compile_instancing

            #include "Assets/Cookbook/Ch12/Ch12Common.hlsl"

            struct MaterialCtx
            {
                float3 N, V;
                float3 albedo;
                float  thickness;   // 0 = 极薄，1 = 不透光
                float  a;
            };

            //#region shade
            half3 ShadeOneLight(MaterialCtx m, Light light)
            {
                float3 L = light.direction;
                float NoL = saturate(dot(m.N, L));
                float3 front = (m.albedo * ADV_INV_PI + AdvSpecularGGX(m.N, m.V, L, m.a, 0.04)) * PI * NoL;

                // 透射：把光方向沿法线“扭”一点（模拟光在叶片内部的散射偏折），
                // 再看视线与 -L' 的接近程度——正对着光源看时最亮
                float3 Lt = normalize(L + m.N * _Distortion);
                float VoLt = pow(saturate(dot(m.V, -Lt)), _TransPower) * _TransScale;
                float3 trans = (VoLt + _TransAmbient) * (1.0 - m.thickness) * _TransColor.rgb * m.albedo * _Transmission;

                // 透射光走的是“叶片背面”的阴影：正面阴影图对它没有意义，这里只用距离衰减
                return front * light.color * (light.distanceAttenuation * light.shadowAttenuation)
                     + trans * light.color * light.distanceAttenuation;
            }
            //#endregion

            #include "Assets/Cookbook/Ch12/LightLoop.hlsl"

            half4 frag(Varyings i, bool isFront : SV_IsFrontFace) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                float2 leaf = LeafShape(i.uv);
                clip(leaf.x);

                float3 T, B, N; Ch12BuildFrame(i, T, B, N);
                N = isFront ? N : -N;   // 背面要翻转法线，否则背面的光照是反的
                float3 V = GetWorldSpaceNormalizeViewDir(i.positionWS);
                float2 screenUV = GetNormalizedScreenSpaceUV(i.positionCS);

                MaterialCtx m;
                m.N = N; m.V = V;
                m.albedo = lerp(_BaseColor.rgb, _VeinColor.rgb, leaf.y * 0.6);
                m.thickness = _UseThickness > 0.5 ? leaf.y * 0.85 : 0.0;
                float pr = 1.0 - _Smoothness;
                m.a = max(pr * pr, 0.002);

                half3 color = AccumulateDirectLighting(m, i.positionWS, screenUV);
                color += SampleSH(N) * m.albedo;

                color = MixFog(color, i.fogFactor);
                return half4(color, 1);
            }
            ENDHLSL
        }

        //#region shadowpass
        // 叶片形状是程序化裁剪的，URP 自带的 ShadowCaster 不知道，所以自己写一个带 clip 的
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0 Cull Off
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
            float3 _LightDirection;
            float3 _LightPosition;
            struct A { float4 positionOS : POSITION; float3 normalOS : NORMAL; float2 uv : TEXCOORD0; UNITY_VERTEX_INPUT_INSTANCE_ID };
            struct V { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; };
            V vert(A v)
            {
                UNITY_SETUP_INSTANCE_ID(v);
                V o;
                float3 positionWS = TransformObjectToWorld(v.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(v.normalOS);
            #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                float3 L = normalize(_LightPosition - positionWS);
            #else
                float3 L = _LightDirection;
            #endif
                o.positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, L));
            #if UNITY_REVERSED_Z
                o.positionCS.z = min(o.positionCS.z, UNITY_NEAR_CLIP_VALUE);
            #else
                o.positionCS.z = max(o.positionCS.z, UNITY_NEAR_CLIP_VALUE);
            #endif
                o.uv = v.uv;
                return o;
            }
            half4 frag(V i) : SV_Target { clip(LeafShape(i.uv).x); return 0; }
            ENDHLSL
        }
        //#endregion
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R Cull Off
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            struct A { float4 positionOS : POSITION; float2 uv : TEXCOORD0; UNITY_VERTEX_INPUT_INSTANCE_ID };
            struct V { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; };
            V vert(A v) { UNITY_SETUP_INSTANCE_ID(v); V o; o.positionCS = TransformObjectToHClip(v.positionOS.xyz); o.uv = v.uv; return o; }
            half frag(V i) : SV_Target { clip(LeafShape(i.uv).x); return i.positionCS.z; }
            ENDHLSL
        }
    }
}
