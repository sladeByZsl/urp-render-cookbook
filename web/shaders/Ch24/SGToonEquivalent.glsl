// 第 24 章：与“Unlit Graph + Custom Function 卡通光照”逐节点等价的手写 Shader（GLSL 版）。
// 用途有两个：
//   1) 让 Custom Function 用到的 .hlsl 在普通 Shader 里真实编译一遍（_float 和 _half 两套都调用到）；
//   2) 渲染书中的效果图（Shader Graph 资源无法在批处理里手写生成）。
// SHADERGRAPH_PREVIEW 在这里被声明成一个本地关键字，只是为了把“预览分支”也编译、也能拍出来看，
// 真正的 Shader Graph 不需要也不应该这样做。
Shader "Cookbook/Ch24/SGToonEquivalent"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform vec4  _BaseColor;
        uniform vec4  _ShadowTint;
        uniform float _Steps;
        uniform float _Smooth;
        uniform vec4  _RimColor;
        uniform float _RimPower;
        uniform float _UseHalf;
        uniform float _AddLights;
        ENDGLSL

        Pass
        {
            Name "Universal Forward"
            Tags { "LightMode"="UniversalForward" }
            GLSLPROGRAM
            // —— 在 Unlit Graph 的 Blackboard 里要手动加的 Keyword（_MAIN_LIGHT_SHADOWS 等）网页引擎始终打开 ——
            #pragma shader_feature_local _ SHADERGRAPH_PREVIEW

            #include "Ch24/CustomLighting.glsl"
            #include "Ch24/StylizedFunctions.glsl"

            VARYING vec3 positionWS;
            VARYING vec3 normalWS;

            #ifdef VERTEX
            void main()
            {
                VertexPositionInputs p = GetVertexPositionInputs(positionOS.xyz);
                gl_Position = p.positionCS; positionWS = p.positionWS;
                normalWS = TransformObjectToWorldNormal(normalOS);
            }
            #endif

            #ifdef FRAGMENT
            //#region graph
            vec4 frag()
            {
                // [Position 节点 World] [Normal Vector 节点 World] [View Direction 节点 World] [Screen Position 节点 Default]
                vec3 posWS = positionWS;
                vec3 nWS = normalize(normalWS);
                vec3 viewWS = GetWorldSpaceNormalizeViewDir(posWS);
                vec2 screenUV = GetNormalizedScreenSpaceUV(gl_FragCoord);

                // [Custom Function: MainLight]
                vec3 lightDir, lightColor; float distAtten, shadowAtten;
                if (_UseHalf > 0.5) MainLight_half(posWS, lightDir, lightColor, distAtten, shadowAtten);
                else MainLight_float(posWS, lightDir, lightColor, distAtten, shadowAtten);

                // [Dot Product] → [Custom Function: ToonRamp]
                float NdotL = dot(nWS, lightDir);
                float ramp;
                if (_UseHalf > 0.5) ToonRamp_half(NdotL, shadowAtten, _Steps, _Smooth, ramp);
                else ToonRamp_float(NdotL, shadowAtten, _Steps, _Smooth, ramp);

                // [Lerp] 阴影色 ↔ 固有色，再乘主光颜色
                vec3 albedo = _BaseColor.rgb;
                vec3 toon = mix(albedo * _ShadowTint.rgb, albedo, ramp) * lightColor;

                // [Custom Function: RimLight] 只在受光侧出现
                float rim;
                RimLight_float(nWS, viewWS, lightDir, _RimPower, 1.0, rim);
                rim *= step(0.5, ramp);   // 阴影里不出边缘光

                // [Custom Function: AdditionalLightsLambert] 点光、聚光
                vec3 extra = vec3(0.0);
                if (_AddLights > 0.5)
                {
                    AdditionalLightsLambert_float(posWS, nWS, screenUV, extra);
                    vec3 extraHalf; AdditionalLightsLambert_half(posWS, nWS, screenUV, extraHalf);
                    extra = _UseHalf > 0.5 ? extraHalf : extra;
                }

                // [Ambient 节点（Equator/Sky）] 这里用等价的 SampleSH
            #if defined(SHADERGRAPH_PREVIEW)
                vec3 ambient = vec3(0.2);
            #else
                vec3 ambient = SampleSH(nWS);
            #endif

                vec3 color = toon + albedo * (ambient * 0.6 + extra) + rim * _RimColor.rgb;
                return vec4(color, 1);   // → Master Stack 的 Base Color
            }
            //#endregion
            void main() { fragColor = frag(); }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0
            GLSLPROGRAM
            #define CH23_SHADOW_PASS
            #include "Ch23/Ch23Common.glsl"
            ENDGLSL
        }
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            GLSLPROGRAM
            #define CH23_DEPTH_PASS
            #include "Ch23/Ch23Common.glsl"
            ENDGLSL
        }
    }
}
