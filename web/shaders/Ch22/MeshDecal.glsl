// 案例 22.8–22.9：网格贴花（Mesh Decal）——贴在表面上的一块真实网格，用深度偏移（Offset）避免 Z-Fighting（GLSL 版）
Shader "Cookbook/Ch22/MeshDecal"
{
    SubShader
    {
        Tags { "RenderType"="Transparent" "RenderPipeline"="UniversalPipeline" "Queue"="Transparent-100" "IgnoreProjector"="True" }

        Pass
        {
            Name "MeshDecal"
            Tags { "LightMode"="UniversalForward" }
            //#region state
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            ZTest LEqual
            // 深度偏移：depth += factor × 斜率 + units × 最小可分辨深度单位
            // 负值 = 往相机方向拉一点，让与底面共面的贴花稳定地赢下深度测试
            Offset [_OffsetFactor], [_OffsetUnits]
            //#endregion

            GLSLPROGRAM
            #pragma shader_feature_local_fragment _NORMALMAP

            uniform vec4 _BaseMap_ST;
            uniform vec4 _BaseColor;
            uniform float _BumpScale, _Smoothness;
            uniform float _OffsetFactor, _OffsetUnits;
            uniform float _DebugColor;
            uniform sampler2D _BaseMap;
            uniform sampler2D _BumpMap;

            VARYING vec3 positionWS;
            VARYING vec3 normalWS;
            VARYING vec4 tangentWS;
            VARYING vec2 uv;

            #ifdef VERTEX
            void main()
            {
                VertexPositionInputs p = GetVertexPositionInputs(positionOS.xyz);
                VertexNormalInputs n = GetVertexNormalInputs(normalOS, tangentOS);
                gl_Position = p.positionCS;
                positionWS = p.positionWS;
                normalWS = n.normalWS;
                tangentWS = vec4(n.tangentWS, tangentOS.w * GetOddNegativeScale());
                uv = TransformTex(texcoord0.xy, _BaseMap_ST);
            }
            #endif

            #ifdef FRAGMENT
            vec4 frag()
            {
                vec4 decal = texture(_BaseMap, uv) * _BaseColor;
                if (_DebugColor > 0.5) return vec4(0.1, 0.8, 1.0, 0.55);   // 调试：显示生成的网格覆盖范围

                vec3 n = normalize(normalWS);
            #if defined(_NORMALMAP)
                vec3 nTS = UnpackNormalScale(texture(_BumpMap, uv), _BumpScale);
                vec3 bitangent = tangentWS.w * cross(normalWS, tangentWS.xyz);
                n = normalize(TransformTangentToWorld(nTS, mat3(tangentWS.xyz, bitangent, normalWS)));
            #endif
                InputData inputData = InitInputData();
                inputData.positionWS = positionWS;
                inputData.normalWS = n;
                inputData.viewDirectionWS = GetWorldSpaceNormalizeViewDir(positionWS);
                inputData.shadowCoord = TransformWorldToShadowCoord(positionWS);
                inputData.bakedGI = SampleSH(n);
                inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(gl_FragCoord);
                inputData.shadowMask = vec4(1, 1, 1, 1);
                SurfaceData s = InitSurfaceData();
                s.albedo = decal.rgb;
                s.metallic = 0.0;
                s.smoothness = _Smoothness;
                s.occlusion = 1.0;
                s.alpha = decal.a;
                vec3 color = UniversalFragmentPBR(inputData, s).rgb;
                return vec4(color, decal.a);
            }
            void main() { fragColor = frag(); }
            #endif
            ENDGLSL
        }
    }
}
