// 基础法线 + 细节法线，四种混合方法可切换（演示用；实际项目里选定一种写死即可）。（GLSL 版，对应 Ch07/DetailNormal.shader）
Shader "Cookbook/Ch07/DetailNormal"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform vec4  _BaseMap_ST;
        uniform vec4  _DetailNormalMap_ST;
        uniform float _BumpScale;
        uniform float _DetailNormalScale;
        uniform float _DetailMask;
        uniform float _BlendMode;
        uniform float _ShowNormal;
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            GLSLPROGRAM
            #include "Ch07/Ch07Common.glsl"
            #include "Ch07/NormalBlend.glsl"

            uniform sampler2D _BaseMap;
            uniform sampler2D _BumpMap;
            uniform sampler2D _DetailNormalMap;

            VARYING vec4 uv;   // xy 基础 UV，zw 细节 UV（细节贴图通常平铺得更密）
            VARYING vec3 positionWS;
            VARYING vec3 normalWS;
            VARYING vec4 tangentWS;

            #ifdef VERTEX
            void main()
            {
                VertexPositionInputs pos = GetVertexPositionInputs(positionOS.xyz);
                VertexNormalInputs nrm = GetVertexNormalInputs(normalOS, tangentOS);
                gl_Position = pos.positionCS;
                positionWS = pos.positionWS;
                uv.xy = TransformTex(texcoord0.xy, _BaseMap_ST);
                uv.zw = TransformTex(texcoord0.xy, _DetailNormalMap_ST);
                normalWS = nrm.normalWS;
                tangentWS = vec4(nrm.tangentWS, tangentOS.w * GetOddNegativeScale());
            }
            #endif

            //#region frag
            #ifdef FRAGMENT
            void main()
            {
                vec3 n1 = UnpackNormalScale(texture(_BumpMap, uv.xy), _BumpScale);
                vec3 n2 = UnpackNormalScale(texture(_DetailNormalMap, uv.zw), _DetailNormalScale);
                n1 = normalize(n1);
                n2 = normalize(n2);

                vec3 blended;
                if (_BlendMode < 0.5)      blended = BlendNormalLinear(n1, n2);
                else if (_BlendMode < 1.5) blended = BlendNormalUDN(n1, n2);
                else if (_BlendMode < 2.5) blended = BlendNormalWhiteout(n1, n2);
                else if (_BlendMode < 3.5) blended = BlendNormalReoriented(n1, n2);
                else if (_BlendMode < 4.5) blended = n1;
                else                       blended = n2;
                // 遮罩：与 URP Lit 一样在“只有基础法线”和“混合结果”之间插值
                vec3 normalTS = normalize(mix(n1, blended, _DetailMask));

                vec3 bitangent = tangentWS.w * cross(normalWS, tangentWS.xyz);
                vec3 nWS = NormalizeNormalPerPixel(
                    TransformTangentToWorld(normalTS, mat3(tangentWS.xyz, bitangent, normalWS)));

                if (_ShowNormal > 0.5) { fragColor = vec4(normalTS * 0.5 + 0.5, 1.0); return; }   // 直接看切线空间结果
                vec3 albedo = texture(_BaseMap, uv.xy).rgb;
                fragColor = vec4(Ch07Shade(positionWS, nWS, albedo, 0.5, 0.2, 1.0), 1.0);
            }
            #endif
            //#endregion
            ENDGLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0
            GLSLPROGRAM
            #define CH07_SHADOW_PASS
            #include "Ch07/Ch07Common.glsl"
            ENDGLSL
        }
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            GLSLPROGRAM
            #define CH07_DEPTH_PASS
            #include "Ch07/Ch07Common.glsl"
            ENDGLSL
        }
    }
}
