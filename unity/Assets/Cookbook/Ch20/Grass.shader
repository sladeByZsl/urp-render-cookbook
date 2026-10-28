// 案例 20.7–20.9：GPU Instancing 草——每实例颜色变化、交互压弯、距离淡出
Shader "Cookbook/Ch20/Grass"
{
    Properties
    {
        _RootColor ("Root Color", Color) = (0.05, 0.12, 0.03, 1)
        _TipColor ("Tip Color", Color) = (0.35, 0.55, 0.12, 1)
        _DryColor ("Dry Color", Color) = (0.55, 0.5, 0.2, 1)
        _DryAmount ("Dry Amount", Range(0, 1)) = 0.35
        _Translucency ("Translucency", Range(0, 2)) = 0.6
        _NormalUp ("Normal Towards Up", Range(0, 1)) = 0.5
        _WindDir ("Wind Dir (XZ)", Vector) = (1, 0, 0.3, 0)
        _WindStrength ("Wind Strength", Range(0, 0.5)) = 0.1
        _WindSpeed ("Wind Speed", Float) = 1.5
        _WindPhase ("Wind Phase (for stills)", Float) = 0
        _BendStrength ("Interact Bend", Range(0, 2)) = 0.9
        _PressDown ("Interact Press Down", Range(0, 1)) = 0.3
        _FadeStart ("Fade Start (m)", Float) = 18
        _FadeEnd ("Fade End (m)", Float) = 24
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }
        Cull Off    // 草叶是单层面片，两面都要画

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        CBUFFER_START(UnityPerMaterial)
            half4 _RootColor, _TipColor, _DryColor;
            half _DryAmount, _Translucency, _NormalUp;
            float4 _WindDir;
            float _WindStrength, _WindSpeed, _WindPhase;
            float _BendStrength, _PressDown;
            float _FadeStart, _FadeEnd;
        CBUFFER_END

        //#region instanceProps
        // 每实例属性：C# 用 MaterialPropertyBlock.SetFloatArray("_Variation", ...) 按批传入
        UNITY_INSTANCING_BUFFER_START(GrassProps)
            UNITY_DEFINE_INSTANCED_PROP(float, _Variation)
        UNITY_INSTANCING_BUFFER_END(GrassProps)
        //#endregion

        //#region globals
        // 交互体：全局数组，xyz = 世界坐标，w = 影响半径。不放进 UnityPerMaterial，由 Shader.SetGlobal* 设置
        float4 _Ch20Interactors[8];
        float  _Ch20InteractorCount;
        //#endregion

        struct GrassAttributes
        {
            float4 positionOS : POSITION;
            float3 normalOS   : NORMAL;
            float4 color      : COLOR;
            float2 uv         : TEXCOORD0;
            UNITY_VERTEX_INPUT_INSTANCE_ID
        };

        //#region deform
        // 返回变形后的世界坐标；fade 为距离淡出系数（1 = 完全可见）
        float3 GrassDeform(GrassAttributes v, out float fade)
        {
            float3 pivotWS = TransformObjectToWorld(float3(0, 0, 0));     // 这一丛草的根部中心
            // 1) 距离淡出：先把整丛草“压矮”，再配合片元里的抖动裁剪
            float camDist = distance(pivotWS, GetCameraPositionWS());
            fade = saturate((_FadeEnd - camDist) / max(_FadeEnd - _FadeStart, 1e-3));
            float3 posOS = v.positionOS.xyz;
            posOS.y *= lerp(0.3, 1.0, fade);
            float3 posWS = TransformObjectToWorld(posOS);

            float h = v.uv.y;            // 0 根部 → 1 叶尖
            float bendW = h * h;         // 根部钉死、越往上越软（平方让弯曲更像弧线）

            // 2) 风：简化的行波（完整的风场做法见第 17 章）。_WindPhase 供静帧拍摄用
            float phase = _WindPhase + _Time.y * _WindSpeed;
            float wave = sin(dot(pivotWS.xz, float2(0.35, 0.22)) + phase) * 0.5 + 0.5;
            wave += sin(dot(pivotWS.xz, float2(-1.3, 0.9)) + phase * 2.3) * 0.15;
            posWS.xz += normalize(_WindDir.xz) * (wave * _WindStrength * bendW);

            // 3) 交互：每个交互体把附近的草沿水平方向推开，并往下压
            float2 push = 0;
            float press = 0;
            int count = (int)_Ch20InteractorCount;
            for (int k = 0; k < count; k++)
            {
                float4 it = _Ch20Interactors[k];
                float2 d = posWS.xz - it.xz;
                float dist = length(d);
                float f = saturate(1.0 - dist / it.w);
                f = f * f * (3.0 - 2.0 * f);                         // smoothstep 形状，边缘不突变
                f *= saturate(1.0 - (pivotWS.y - it.y) / it.w);      // 交互体离地太高就不影响
                push += d / max(dist, 1e-3) * f;
                press = max(press, f);
            }
            // 水平推开量不超过顶点离地高度；再按“到根部的距离不变”把顶点压低：y' = √(h² − |o|²)
            float hy = max(posWS.y - pivotWS.y, 0.0);
            float2 o = push * (_BendStrength * bendW);
            float ol = length(o);
            float maxO = hy * 0.95;
            o *= min(1.0, maxO / max(ol, 1e-4));
            ol = min(ol, maxO);
            posWS.xz += o;
            posWS.y = pivotWS.y + sqrt(max(hy * hy - ol * ol, 0.0)) * (1.0 - press * _PressDown);
            return posWS;
        }
        //#endregion
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }   // 自定义表面混合，没有 GBuffer Pass：Deferred 下也走前向
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #pragma multi_compile _ _FORWARD_PLUS
            #pragma multi_compile_fog
            #pragma multi_compile_instancing

            #include "Assets/Cookbook/Ch20/TerrainCommon.hlsl"

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                half3  normalWS   : TEXCOORD1;
                float4 data       : TEXCOORD2;   // x = 高度 uv.y, y = 颜色随机值, z = 距离淡出, w = 雾
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            Varyings vert(GrassAttributes v)
            {
                Varyings o = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, o);
                float fade;
                float3 posWS = GrassDeform(v, fade);
                o.positionWS = posWS;
                o.positionCS = TransformWorldToHClip(posWS);
                o.normalWS = TransformObjectToWorldNormal(v.normalOS);
                // 每实例随机值 + 每片叶子的随机值，组合出颜色变化
                float variation = UNITY_ACCESS_INSTANCED_PROP(GrassProps, _Variation);
                o.data = float4(v.uv.y, frac(variation + v.color.r * 0.5), fade, ComputeFogFactor(o.positionCS.z));
                return o;
            }

            //#region dither
            // 4×4 Bayer 抖动阈值（0..1）：按屏幕像素位置给出不同阈值，用 clip 做“半透明”
            float Bayer4x4(float2 pixel)
            {
                const float m[16] = { 0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5 };
                uint2 p = uint2(pixel) % 4;
                return (m[p.y * 4 + p.x] + 0.5) / 16.0;
            }
            //#endregion

            //#region frag
            half4 frag(Varyings i, FRONT_FACE_TYPE face : FRONT_FACE_SEMANTIC) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                // 距离淡出的后半段：抖动裁剪，避免草在某个距离“啪”地整片消失
                clip(i.data.z - Bayer4x4(i.positionCS.xy));

                float h = i.data.x;
                half3 albedo = lerp(_RootColor.rgb, _TipColor.rgb, h);
                albedo = lerp(albedo, _DryColor.rgb * lerp(0.6, 1.0, h), smoothstep(1.0 - _DryAmount, 1.0, i.data.y));
                albedo *= lerp(0.85, 1.15, frac(i.data.y * 7.31));

                // 双面：背面翻转法线；再往“上”方向拉，让整片草地的明暗更柔和统一
                half3 n = normalize(i.normalWS) * (IS_FRONT_VFACE(face, 1, -1));
                n = normalize(lerp(n, half3(0, 1, 0), _NormalUp));
                half occlusion = lerp(0.35, 1.0, h);    // 根部互相遮挡，压暗
                half4 color = Ch20ShadePBR(i.positionWS, n, i.positionCS, albedo, 0, 0.2, occlusion, i.data.w);

                // 逆光透射：视线与光线方向接近相反时，叶尖透出亮绿色
                Light mainLight = GetMainLight(TransformWorldToShadowCoord(i.positionWS));
                half3 V = GetWorldSpaceNormalizeViewDir(i.positionWS);
                half back = pow(saturate(dot(V, -mainLight.direction)), 4.0);
                color.rgb += albedo * mainLight.color * (mainLight.shadowAttenuation * back * _Translucency * h);
                return color;
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
            #pragma vertex shadowVert
            #pragma fragment shadowFrag
            #pragma multi_compile_instancing
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"   // Shadows.hlsl 用到其中的 LerpWhiteTo
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
            float3 _LightDirection;
            float3 _LightPosition;

            // 阴影 Pass 必须做同样的顶点变形，否则影子不跟着草动
            float4 shadowVert(GrassAttributes v) : SV_POSITION
            {
                UNITY_SETUP_INSTANCE_ID(v);
                float fade;
                float3 posWS = GrassDeform(v, fade);
                float3 normalWS = TransformObjectToWorldNormal(v.normalOS);
            #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                float3 lightDir = normalize(_LightPosition - posWS);
            #else
                float3 lightDir = _LightDirection;
            #endif
                float4 positionCS = TransformWorldToHClip(ApplyShadowBias(posWS, normalWS, lightDir));
            #if UNITY_REVERSED_Z
                positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
            #else
                positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
            #endif
                return positionCS;
            }
            half4 shadowFrag() : SV_Target { return 0; }
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            HLSLPROGRAM
            #pragma vertex depthVert
            #pragma fragment depthFrag
            #pragma multi_compile_instancing
            float4 depthVert(GrassAttributes v) : SV_POSITION
            {
                UNITY_SETUP_INSTANCE_ID(v);
                float fade;
                return TransformWorldToHClip(GrassDeform(v, fade));
            }
            half4 depthFrag() : SV_Target { return 0; }
            ENDHLSL
        }
    }
}
