// 使用“手工烘焙”的光照贴图作为间接漫反射，直接光（主光 + 实时阴影）照常实时计算——（GLSL 版，对应 Ch08/ManualLightmap.shader）
// 这正是 Mixed Lighting 里 Baked Indirect 模式的分工。
Shader "Cookbook/Ch08/ManualLightmap"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }
        GLSLINCLUDE
        uniform vec4  _BaseMap_ST;
        uniform vec4  _BaseColor;
        uniform float _Mode;
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            GLSLPROGRAM
            uniform sampler2D _BaseMap;
            uniform sampler2D _BakedGI;

            VARYING vec4 uv;           // xy 贴图 UV，zw 光照贴图 UV
            VARYING vec3 positionWS;
            VARYING vec3 normalWS;

            #ifdef VERTEX
            void main()
            {
                positionWS = TransformObjectToWorld(positionOS.xyz);
                gl_Position = TransformWorldToHClip(positionWS);
                normalWS = TransformObjectToWorldNormal(normalOS);
                uv.xy = TransformTex(texcoord0.xy, _BaseMap_ST);
                uv.zw = texcoord1.xy;      // 真正的光照贴图还要乘 unity_LightmapST，这里一张图只给一个物体用
            }
            #endif

            #ifdef FRAGMENT
            //#region frag
            void main()
            {
                vec3 N = normalize(normalWS);
                vec3 albedo = texture(_BaseMap, uv.xy).rgb * _BaseColor.rgb;
                vec3 baked = texture(_BakedGI, uv.zw).rgb;
                if (_Mode > 1.5) { fragColor = vec4(baked, 1.0); return; }   // 直接看光照贴图里存了什么

                // 间接漫反射：光照贴图（含天空遮蔽） 或 球谐（处处一样，没有遮蔽）
                vec3 indirect = _Mode > 0.5 ? baked : SampleSH(N);
                // 直接光：实时主光 + 实时阴影
                Light mainLight = GetMainLight(TransformWorldToShadowCoord(positionWS));
                vec3 direct = mainLight.color * saturate(dot(N, mainLight.direction)) * mainLight.shadowAttenuation;
                fragColor = vec4(albedo * (indirect + direct), 1.0);
            }
            //#endregion
            #endif
            ENDGLSL
        }
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            GLSLPROGRAM
            #include "Ch08/Ch08Passes.glsl"
            #ifdef VERTEX
            void main() { gl_Position = Ch08DepthVert(); }
            #endif
            #ifdef FRAGMENT
            void main() { fragColor = Ch08NullFrag(); }
            #endif
            ENDGLSL
        }
    }
}
