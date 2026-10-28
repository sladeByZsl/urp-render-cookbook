// URP 的 Unlit 着色器（Unlit.shader）的 GLSL 版本
Shader "Universal Render Pipeline/Unlit"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" }
        GLSLINCLUDE
        uniform sampler2D _BaseMap; uniform vec4 _BaseMap_ST;
        uniform vec4 _BaseColor;
        uniform float _Cutoff;
        ENDGLSL

        Pass
        {
            Name "Unlit"
            Blend [_SrcBlend] [_DstBlend]
            ZWrite [_ZWrite]
            Cull [_Cull]
            GLSLPROGRAM
            #pragma shader_feature_local_fragment _SURFACE_TYPE_TRANSPARENT
            #pragma shader_feature_local_fragment _ALPHATEST_ON
            #pragma shader_feature_local_fragment _ALPHAPREMULTIPLY_ON
            VARYING vec2 uv;
            VARYING float fogFactor;
            #ifdef VERTEX
            void main()
            {
                gl_Position = TransformObjectToHClip(positionOS.xyz);
                uv = TransformTex(texcoord0.xy, _BaseMap_ST);
                fogFactor = ComputeFogFactor(gl_Position.z);
            }
            #endif
            #ifdef FRAGMENT
            void main()
            {
                vec4 texColor = texture(_BaseMap, uv);
                vec3 color = texColor.rgb * _BaseColor.rgb;
                float alpha = texColor.a * _BaseColor.a;
            #ifdef _ALPHATEST_ON
                if (alpha < _Cutoff) discard;
            #endif
            #ifdef _ALPHAPREMULTIPLY_ON
                color *= alpha;
            #endif
                color = MixFog(color, fogFactor);
            #ifndef _SURFACE_TYPE_TRANSPARENT
                alpha = 1.0;
            #endif
                fragColor = vec4(color, alpha);
            }
            #endif
            ENDGLSL
        }
        // URP 的 Unlit.shader 没有 ShadowCaster Pass（Unlit 物体不投影），这里也不加
        UsePass "Cookbook/Common/DEPTHONLY"
    }
}
