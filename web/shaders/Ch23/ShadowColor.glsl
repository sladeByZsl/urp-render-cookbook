// 案例 23.6：自定义阴影颜色（GLSL 版）。
// 思路：不再用“阴影 = 光照乘一个 0~1 的系数”，而是在“受光色”和“阴影色”之间插值，
// 让被遮挡区域呈现指定的色相（冷色阴影、卡通紫影等），同时保留 URP 的级联、软阴影和距离淡出。
Shader "Cookbook/Ch23/ShadowColor"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform vec4  _BaseMap_ST;
        uniform vec4  _BaseColor;
        uniform vec4  _ShadowColor;
        uniform float _AmbientScale;
        uniform float _TintTerminator;
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            GLSLPROGRAM
            uniform sampler2D _BaseMap;

            VARYING vec2  uv;
            VARYING vec3  positionWS;
            VARYING vec3  normalWS;
            VARYING float fogFactor;

            #ifdef VERTEX
            void main()
            {
                VertexPositionInputs p = GetVertexPositionInputs(positionOS.xyz);
                gl_Position = p.positionCS;
                positionWS  = p.positionWS;
                normalWS    = TransformObjectToWorldNormal(normalOS);
                uv          = TransformTex(texcoord0.xy, _BaseMap_ST);
                fogFactor   = ComputeFogFactor(p.positionCS.z);
            }
            #endif

            #ifdef FRAGMENT
            //#region frag
            vec4 frag()
            {
                vec3 albedo = texture(_BaseMap, uv).rgb * _BaseColor.rgb;
                vec3 n = normalize(normalWS);

                // 逐像素求阴影坐标：同时兼容单级联 / 多级联 / 屏幕空间阴影
                vec4 shadowCoord = TransformWorldToShadowCoord(positionWS);
                // 带 positionWS 的重载会顺带处理“阴影距离淡出”（GetMainLightShadowFade）
                Light mainLight = GetMainLight(shadowCoord, positionWS, vec4(1, 1, 1, 1));

                float NdotL  = saturate(dot(n, mainLight.direction));
                float shadow = mainLight.shadowAttenuation;

                // lit：0 = 完全不受光，1 = 完全受光
                // _TintTerminator=1 时背光面（NdotL 小）也算“阴影”，整体风格更统一；
                // _TintTerminator=0 时只给投射阴影上色，明暗交界线保持 Lambert 的自然过渡
                float lit = _TintTerminator > 0.5 ? NdotL * shadow : shadow;
                vec3 shadowTint = mix(vec3(0, 0, 0), _ShadowColor.rgb, _ShadowColor.a);
                vec3 direct = mix(shadowTint, mainLight.color, lit);
                if (_TintTerminator < 0.5) direct *= NdotL;  // 只染投射阴影时仍需要 N·L

                vec3 ambient = SampleSH(n) * _AmbientScale;
                vec3 color = albedo * (direct + ambient);
                color = MixFog(color, fogFactor);
                return vec4(color, 1);
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
