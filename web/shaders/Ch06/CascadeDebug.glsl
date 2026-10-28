// 案例 6.6 级联阴影可视化：按像素所在的级联染色（GLSL 版，对应 Ch06/CascadeDebug.shader）
// 级联包围球 _CascadeShadowSplitSpheres0~3 由引擎按 Asset 的级联数、分割比例和阴影距离算好（与 URP 同名）。
Shader "Cookbook/Ch06/CascadeDebug"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform vec4  _BaseMap_ST;
        uniform vec4  _BaseColor;
        uniform float _TintStrength;
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            GLSLPROGRAM
            uniform sampler2D _BaseMap;

            VARYING vec2 uv;
            VARYING vec3 positionWS;
            VARYING vec3 normalWS;

            #ifdef VERTEX
            void main()
            {
                VertexPositionInputs pos = GetVertexPositionInputs(positionOS.xyz);
                gl_Position = pos.positionCS;
                positionWS = pos.positionWS;
                normalWS = TransformObjectToWorldNormal(normalOS);
                uv = TransformTex(texcoord0.xy, _BaseMap_ST);
            }
            #endif

            #ifdef FRAGMENT
            //#region frag
            void main()
            {
                vec3 albedo = texture(_BaseMap, uv).rgb * _BaseColor.rgb;
                vec3 N = normalize(normalWS);

                Light mainLight = GetMainLight(TransformWorldToShadowCoord(positionWS));
                vec3 color = albedo * mainLight.color * mainLight.shadowAttenuation * saturate(dot(N, mainLight.direction));
                color += albedo * SampleSH(N) * 0.4;

                // ComputeCascadeIndex：依次判断像素是否落在 4 个“级联包围球”里，返回第一个命中的序号；
                // 4 表示超出了所有级联（阴影距离之外）。
                // HLSL 版用 _MAIN_LIGHT_SHADOWS_CASCADE 关键字区分；GLSL 版里它是 uniform：_MainLightShadowsCascade > 0.5
                float cascade = 0.0;   // 只有一个级联时 URP 不会更新包围球数据，直接当作第 0 级
                if (_MainLightShadowsCascade > 0.5) cascade = ComputeCascadeIndex(positionWS);

                const vec3 kCascadeColors[5] = vec3[5](
                    vec3(1.0, 0.25, 0.2), vec3(0.25, 0.85, 0.3), vec3(0.25, 0.45, 1.0), vec3(1.0, 0.85, 0.2), vec3(1, 1, 1)
                );
                vec3 tint = kCascadeColors[int(cascade)];
                color = mix(color, color * tint * 1.6, _TintStrength);
                fragColor = vec4(color, 1.0);
            }
            //#endregion
            #endif
            ENDGLSL
        }

        // ---- 投影与深度：见案例 6.4 与 6.8 ----
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On
            ZTest LEqual
            ColorMask 0

            GLSLPROGRAM
            #include "Ch06/ShadowCasterPass.glsl"
            ENDGLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On
            ColorMask R

            GLSLPROGRAM
            #include "Ch06/DepthOnlyPass.glsl"
            ENDGLSL
        }
    }
}
