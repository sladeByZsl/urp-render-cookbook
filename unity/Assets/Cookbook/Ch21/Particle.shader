// 案例 21.5–21.7：通用粒子 Shader——顶点色、混合模式、Custom Vertex Streams 帧间混合、软粒子、近相机淡出、渐变映射
Shader "Cookbook/Ch21/Particle"
{
    Properties
    {
        [MainTexture] _BaseMap ("Texture", 2D) = "white" {}
        [HDR] _BaseColor ("Tint", Color) = (1,1,1,1)
        [Enum(UnityEngine.Rendering.BlendMode)] _SrcBlend ("Src Blend", Float) = 5     // SrcAlpha
        [Enum(UnityEngine.Rendering.BlendMode)] _DstBlend ("Dst Blend", Float) = 10    // OneMinusSrcAlpha
        [Toggle] _Premultiply ("Premultiply RGB by Alpha", Float) = 0
        [Toggle] _Modulate ("Modulate (for Multiply blend)", Float) = 0
        [Toggle(_FLIPBOOKBLENDING_ON)] _FlipbookBlending ("Flipbook Blending (needs UV2 + AnimBlend streams)", Float) = 0
        [Toggle(_SOFTPARTICLES_ON)] _SoftParticles ("Soft Particles", Float) = 0
        _SoftDistance ("Soft Distance (m)", Float) = 0.5
        [Toggle(_CAMERAFADE_ON)] _CameraFade ("Camera Near Fade", Float) = 0
        _CameraFadeNear ("Fade Near (m)", Float) = 0.3
        _CameraFadeFar ("Fade Far (m)", Float) = 1.5
        [Toggle(_RAMP_ON)] _UseRamp ("Color Ramp (fire)", Float) = 0
        [NoScaleOffset] _RampTex ("Ramp", 2D) = "white" {}
        _RampScale ("Ramp Input Scale", Float) = 1.5
    }
    SubShader
    {
        Tags { "RenderType"="Transparent" "RenderPipeline"="UniversalPipeline" "Queue"="Transparent" "IgnoreProjector"="True" "PreviewType"="Plane" }

        Pass
        {
            Name "ForwardUnlit"
            Tags { "LightMode"="UniversalForward" }
            Blend [_SrcBlend] [_DstBlend]
            ZWrite Off
            Cull Off
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma shader_feature_local _FLIPBOOKBLENDING_ON
            #pragma shader_feature_local _SOFTPARTICLES_ON
            #pragma shader_feature_local _CAMERAFADE_ON
            #pragma shader_feature_local_fragment _RAMP_ON
            #pragma multi_compile_fog
            #pragma multi_compile_instancing
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                half4 _BaseColor;
                half _Premultiply, _Modulate;
                float _SoftDistance, _CameraFadeNear, _CameraFadeFar;
                half _RampScale;
            CBUFFER_END
            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);
            TEXTURE2D(_RampTex); SAMPLER(sampler_RampTex);

            //#region streams
            // 与粒子系统 Renderer › Custom Vertex Streams 的顺序一一对应：
            //   Position(POSITION) · Color(COLOR) · UV(TEXCOORD0.xy) · UV2(TEXCOORD0.zw) · AnimBlend(TEXCOORD1.x)
            struct Attributes
            {
                float4 positionOS : POSITION;
                half4  color      : COLOR;
            #if defined(_FLIPBOOKBLENDING_ON)
                float4 texcoords  : TEXCOORD0;   // xy = 当前帧 UV，zw = 下一帧 UV
                float  animBlend  : TEXCOORD1;   // 两帧之间的进度 0..1
            #else
                float2 texcoords  : TEXCOORD0;
            #endif
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            //#endregion

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                half4  color      : COLOR;
                float4 uv         : TEXCOORD0;   // xy 当前帧，zw 下一帧
                float4 screenData : TEXCOORD1;   // xyw = positionNDC，z = 自身观察空间深度
                float2 extra      : TEXCOORD2;   // x = 帧混合系数，y = 雾
            };

            Varyings vert(Attributes v)
            {
                Varyings o = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(v);
                VertexPositionInputs p = GetVertexPositionInputs(v.positionOS.xyz);
                o.positionCS = p.positionCS;
                o.color = v.color;
            #if defined(_FLIPBOOKBLENDING_ON)
                o.uv = float4(TRANSFORM_TEX(v.texcoords.xy, _BaseMap), TRANSFORM_TEX(v.texcoords.zw, _BaseMap));
                o.extra.x = v.animBlend;
            #else
                o.uv = TRANSFORM_TEX(v.texcoords.xy, _BaseMap).xyxy;
            #endif
                o.screenData = float4(p.positionNDC.xy, -p.positionVS.z, p.positionNDC.w);
                o.extra.y = ComputeFogFactor(p.positionCS.z);
                return o;
            }

            //#region frag
            half4 frag(Varyings i) : SV_Target
            {
                half4 tex = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv.xy);
            #if defined(_FLIPBOOKBLENDING_ON)
                half4 tex2 = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv.zw);
                tex = lerp(tex, tex2, i.extra.x);
            #endif

                // 顶点色 = 粒子系统的 Start Color × Color over Lifetime：整个粒子系统的颜色变化都从这里进来
                half4 c = tex * i.color * _BaseColor;

            #if defined(_RAMP_ON)
                // 渐变映射：用“贴图浓度 × 粒子剩余寿命（顶点色 alpha）”去查火焰渐变，越老越暗红
                half k = saturate(tex.a * i.color.a * _RampScale);
                c.rgb = SAMPLE_TEXTURE2D(_RampTex, sampler_RampTex, float2(k, 0.5)).rgb * _BaseColor.rgb;
                c.a = saturate(k);
            #endif

                float thisZ = i.screenData.z;
            #if defined(_SOFTPARTICLES_ON)
                // 软粒子：比较场景深度与粒子自身深度，越接近（快要插进物体）越透明
                float2 suv = i.screenData.xy / i.screenData.w;
                float sceneZ = LinearEyeDepth(SampleSceneDepth(suv), _ZBufferParams);
                c.a *= saturate((sceneZ - thisZ) / _SoftDistance);
            #endif
            #if defined(_CAMERAFADE_ON)
                // 近相机淡出：粒子贴脸时会糊满屏幕、产生巨大 Overdraw，提前淡掉
                c.a *= saturate((thisZ - _CameraFadeNear) / max(_CameraFadeFar - _CameraFadeNear, 1e-3));
            #endif

                c.rgb *= lerp(1.0, c.a, _Premultiply);   // 预乘：Blend One OneMinusSrcAlpha 时需要
                // 正片叠底（Blend DstColor Zero）没有 alpha 参与：把 alpha 折算进颜色，透明处趋向白色（=不改变背景）
                c.rgb = lerp(c.rgb, lerp(1.0, c.rgb, c.a), _Modulate);
                // 雾：Alpha 混合直接 MixFog；叠加模式应往黑色雾化 MixFogColor(c.rgb, 0, fog)，否则雾里越叠越亮
                c.rgb = MixFog(c.rgb, i.extra.y);
                return c;
            }
            //#endregion
            ENDHLSL
        }
    }
}
