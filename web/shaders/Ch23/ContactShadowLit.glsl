// 案例 23.9：接收接触阴影的简单光照 Shader（GLSL 版）。
// 阴影 = min(阴影贴图结果, 接触阴影结果)：远处的大阴影交给 Shadow Map，脚底的细节交给接触阴影。
Shader "Cookbook/Ch23/ContactShadowLit"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }
        GLSLINCLUDE
        uniform vec4  _BaseMap_ST;
        uniform vec4  _BaseColor;
        uniform float _UseContact;
        uniform float _ShowContact;
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }
            GLSLPROGRAM
            uniform sampler2D _BaseMap;
            uniform sampler2D _ContactShadowTexture;   // 由 ContactShadowFeature 设成全局纹理

            VARYING vec2 uv;
            VARYING vec3 positionWS;
            VARYING vec3 normalWS;

            #ifdef VERTEX
            void main()
            {
                VertexPositionInputs p = GetVertexPositionInputs(positionOS.xyz);
                gl_Position = p.positionCS; positionWS = p.positionWS;
                normalWS = TransformObjectToWorldNormal(normalOS);
                uv = TransformTex(texcoord0.xy, _BaseMap_ST);
            }
            #endif

            #ifdef FRAGMENT
            //#region frag
            vec4 frag()
            {
                vec3 albedo = texture(_BaseMap, uv).rgb * _BaseColor.rgb;
                vec3 n = normalize(normalWS);
                Light l = GetMainLight(TransformWorldToShadowCoord(positionWS), positionWS, vec4(1, 1, 1, 1));

                float contact = 1.0;
                if (_UseContact > 0.5)
                {
                    vec2 screenUV = GetNormalizedScreenSpaceUV(gl_FragCoord);
                    contact = texture(_ContactShadowTexture, screenUV).r;
                }
                if (_ShowContact > 0.5) return vec4(vec3(contact), 1);

                float shadow = min(l.shadowAttenuation, contact);
                vec3 c = albedo * (l.color * saturate(dot(n, l.direction)) * shadow + SampleSH(n));
                return vec4(c, 1);
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
