// 面部 SDF 阴影：脸上的明暗交界不再由法线决定，而是查一张“阈值图”——
// 图里每个像素存的是“光从正面转到多少度时，这里开始进入阴影”。
Shader "Cookbook/Ch14/ToonFace"
{
    Properties
    {
        [MainColor] _BaseColor ("Skin Color", Color) = (1.0, 0.86, 0.78, 1)
        _ShadeColor ("Shade Color", Color) = (0.9, 0.62, 0.62, 1)
        [KeywordEnum(Normal, SDF)] _FaceShadow ("Face Shadow", Float) = 1
        [NoScaleOffset] _FaceSdf ("Face Threshold Map (R)", 2D) = "white" {}
        _SdfSoftness ("Edge Softness", Range(0, 0.1)) = 0.01
        [Toggle] _DrawFeatures ("Draw Eyes/Mouth", Float) = 1
        _OutlineColor ("Outline Color", Color) = (0.15, 0.1, 0.12, 1)
        _OutlineWidth ("Outline Width (px)", Range(0, 10)) = 0
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
        CBUFFER_START(UnityPerMaterial)
            half4 _BaseColor, _ShadeColor;
            half  _SdfSoftness, _DrawFeatures;
            half4 _OutlineColor;
            half  _OutlineWidth;
        CBUFFER_END
        TEXTURE2D(_FaceSdf); SAMPLER(sampler_FaceSdf);
        ENDHLSL

        Pass
        {
            Name "ToonForward"
            Tags { "LightMode"="UniversalForwardOnly" }

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex ToonVert
            #pragma fragment frag
            #pragma shader_feature_local_fragment _FACESHADOW_NORMAL _FACESHADOW_SDF
            #pragma multi_compile_fog
            #pragma multi_compile_instancing
            #include "Assets/Cookbook/Ch14/ToonCommon.hlsl"

            // 简笔五官（只为让球看起来像一张脸）：两只眼睛、腮红和嘴
            half3 DrawFeatures(half3 color, float2 uv, float frontMask)
            {
                float2 e1 = (uv - float2(0.36, 0.56)) / float2(0.045, 0.07);
                float2 e2 = (uv - float2(0.64, 0.56)) / float2(0.045, 0.07);
                float eye = step(min(dot(e1, e1), dot(e2, e2)), 1.0);
                float2 h1 = (uv - float2(0.35, 0.58)) / 0.018, h2 = (uv - float2(0.63, 0.58)) / 0.018;
                float hl = step(min(dot(h1, h1), dot(h2, h2)), 1.0);
                float2 b1 = (uv - float2(0.3, 0.45)) / float2(0.07, 0.035), b2 = (uv - float2(0.7, 0.45)) / float2(0.07, 0.035);
                float blush = smoothstep(1.0, 0.3, min(dot(b1, b1), dot(b2, b2)));
                float2 m = uv - float2(0.5, 0.36);
                float mouth = step(abs(length(m / float2(1, 0.7) + float2(0, 0.05)) - 0.06), 0.006) * step(m.y, -0.005);
                color = lerp(color, color * half3(1.0, 0.75, 0.75), blush * 0.6 * frontMask);
                color = lerp(color, half3(0.18, 0.12, 0.2), max(eye, mouth) * frontMask);
                color = lerp(color, half3(1, 1, 1), hl * frontMask);
                return color;
            }

            //#region frag
            half4 frag(ToonVaryings i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                Light light = GetMainLight();
                float2 faceUV = i.positionOS.xy + 0.5;           // 正面投影：物体空间 xy → 0~1
                half lit;

            #if defined(_FACESHADOW_NORMAL)
                // 对照组：按法线做色阶，鼻子、眼窝的起伏会让阴影边缘碎成一块一块
                half3 N = normalize(i.normalWS);
                lit = ToonBand(dot(N, light.direction) * 0.5 + 0.5, 0.5, 0.01);
            #else
                // 1) 头部的朝向（物体空间 -Z 是脸的正前方，+X 是画面右侧）
                float3 F = normalize(TransformObjectToWorldDir(float3(0, 0, -1)));
                float3 R = normalize(TransformObjectToWorldDir(float3(1, 0, 0)));
                float3 U = normalize(TransformObjectToWorldDir(float3(0, 1, 0)));
                // 2) 光方向投影到头部的水平面，只关心“从哪一侧、转了多少度”
                float3 Lh = light.direction - U * dot(light.direction, U);
                Lh = normalize(Lh + 1e-5);
                float phi = acos(clamp(dot(F, Lh), -1.0, 1.0)) / PI;   // 0 = 正面光，1 = 正背光
                // 3) 阈值图是按“光从右边来”画的，光从左边来就把 U 镜像
                float2 uv = faceUV;
                if (dot(R, Lh) < 0) uv.x = 1.0 - uv.x;
                half threshold = SAMPLE_TEXTURE2D(_FaceSdf, sampler_FaceSdf, uv).r;
                // 4) 当前角度小于该像素的阈值 → 亮
                lit = smoothstep(phi - _SdfSoftness, phi + _SdfSoftness, threshold);
            #endif

                half3 color = lerp(_ShadeColor.rgb, _BaseColor.rgb, lit) * light.color;
                color += SampleSH(half3(0, 0, 0)) * _BaseColor.rgb * 0.25;
                if (_DrawFeatures > 0.5)
                    color = DrawFeatures(color, faceUV, step(i.positionOS.z, 0.0));
                return half4(MixFog(color, i.fogFactor), 1);
            }
            //#endregion
            ENDHLSL
        }

        Pass
        {
            Name "Outline"
            Tags { "LightMode"="SRPDefaultUnlit" }
            Cull Front
            ZWrite On
            HLSLPROGRAM
            #pragma vertex OutlineVert
            #pragma fragment OutlineFrag
            #pragma multi_compile_fog
            #pragma multi_compile_instancing
            #include "Assets/Cookbook/Ch14/ToonOutlinePass.hlsl"
            ENDHLSL
        }
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0 Cull Back
            HLSLPROGRAM
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment
            #pragma multi_compile_instancing
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            // URP 自带的阴影 Pass 只在 _ALPHATEST_ON 时才读 _BaseMap，其余部分与材质无关，直接复用
            #include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"
            ENDHLSL
        }
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R Cull Back
            HLSLPROGRAM
            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment
            #pragma multi_compile_instancing
            #include "Packages/com.unity.render-pipelines.universal/Shaders/DepthOnlyPass.hlsl"
            ENDHLSL
        }
        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode"="DepthNormals" }
            ZWrite On Cull Back
            HLSLPROGRAM
            #pragma vertex DepthNormalsVertex
            #pragma fragment DepthNormalsFragment
            #pragma multi_compile_instancing
            #include "Packages/com.unity.render-pipelines.universal/Shaders/DepthNormalsPass.hlsl"
            ENDHLSL
        }
    }
}
