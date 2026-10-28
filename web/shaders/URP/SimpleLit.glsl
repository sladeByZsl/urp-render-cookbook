// URP 的 Simple Lit 着色器（Blinn-Phong，SimpleLit.shader）的 GLSL 版本
Shader "Universal Render Pipeline/Simple Lit"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" }
        GLSLINCLUDE
        uniform sampler2D _BaseMap; uniform vec4 _BaseMap_ST;
        uniform vec4 _BaseColor;
        uniform float _Cutoff;
        uniform vec4 _SpecColor;
        uniform sampler2D _SpecGlossMap;
        uniform float _Smoothness;
        uniform sampler2D _BumpMap;
        uniform sampler2D _EmissionMap; uniform vec4 _EmissionColor;
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }
            Blend [_SrcBlend] [_DstBlend]
            ZWrite [_ZWrite]
            Cull [_Cull]
            GLSLPROGRAM
            #pragma shader_feature_local_fragment _SURFACE_TYPE_TRANSPARENT
            #pragma shader_feature_local_fragment _ALPHATEST_ON
            #pragma shader_feature_local_fragment _SPECGLOSSMAP _SPECULAR_COLOR
            #pragma shader_feature_local_fragment _EMISSION
            #pragma shader_feature_local _NORMALMAP
            VARYING vec2 uv;
            VARYING vec3 positionWS;
            VARYING vec3 normalWS;
            VARYING vec4 tangentWS;
            #ifdef VERTEX
            void main()
            {
                VertexPositionInputs v = GetVertexPositionInputs(positionOS.xyz);
                VertexNormalInputs n = GetVertexNormalInputs(normalOS, tangentOS);
                uv = TransformTex(texcoord0.xy, _BaseMap_ST);
                positionWS = v.positionWS; normalWS = n.normalWS;
                tangentWS = vec4(n.tangentWS, tangentOS.w * GetOddNegativeScale());
                gl_Position = v.positionCS;
            }
            #endif
            #ifdef FRAGMENT
            void main()
            {
                vec4 albedo = texture(_BaseMap, uv) * _BaseColor;
            #ifdef _ALPHATEST_ON
                if (albedo.a < _Cutoff) discard;
            #endif
                SurfaceData s = InitSurfaceData();
                s.albedo = albedo.rgb; s.alpha = albedo.a;
            #ifdef _SPECGLOSSMAP
                vec4 sg = texture(_SpecGlossMap, uv) * _SpecColor;
                s.specular = sg.rgb; s.smoothness = sg.a * _Smoothness;
            #else
                s.specular = _SpecColor.rgb; s.smoothness = _Smoothness;
            #endif
            #ifdef _EMISSION
                s.emission = texture(_EmissionMap, uv).rgb * _EmissionColor.rgb;
            #endif
                InputData d = InitInputData();
                d.positionWS = positionWS;
            #ifdef _NORMALMAP
                vec3 nTS = UnpackNormal(texture(_BumpMap, uv));
                vec3 b = tangentWS.w * cross(normalWS, tangentWS.xyz);
                d.normalWS = normalize(mat3(tangentWS.xyz, b, normalWS) * nTS);
            #else
                d.normalWS = normalize(normalWS);
            #endif
                d.viewDirectionWS = GetWorldSpaceNormalizeViewDir(positionWS);
                d.shadowCoord = TransformWorldToShadowCoord(positionWS);
                d.bakedGI = SampleSH(d.normalWS);
                d.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(gl_FragCoord);
                vec4 c = UniversalFragmentBlinnPhong(d, s);
            #ifndef _SURFACE_TYPE_TRANSPARENT
                c.a = 1.0;
            #endif
                fragColor = c;
            }
            #endif
            ENDGLSL
        }
        UsePass "Cookbook/Common/SHADOWCASTER"
        UsePass "Cookbook/Common/DEPTHONLY"
        UsePass "Cookbook/Common/DEPTHNORMALS"
    }
}
