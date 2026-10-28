// 背面外扩描边（Back-face Outline / Inverted Hull）。（GLSL 版，对应 Ch14/ToonOutline.shader）
// 第二个 Pass 只画背面，并把顶点沿法线推出去，露出来的一圈就是轮廓线。
Shader "Cookbook/Ch14/ToonOutline"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform vec4 _BaseColor, _ShadeColor, _OutlineColor;
        uniform float _OutlineWidth, _OutlineWidthOS;
        ENDGLSL

        Pass
        {
            Name "ToonForward"
            Tags { "LightMode"="UniversalForwardOnly" }
            GLSLPROGRAM
            #define TOON_VARYINGS
            #include "Ch14/ToonCommon.glsl"
            #ifdef VERTEX
            void main() { ToonVert(); }
            #endif
            #ifdef FRAGMENT
            vec4 frag()
            {
                vec3 N = normalize(normalWS);
                Light light = GetMainLight();
                float band = ToonBand(dot(N, light.direction) * 0.5 + 0.5, 0.5, 0.02);
                vec3 color = mix(_ShadeColor.rgb, _BaseColor.rgb, band) * light.color;
                color += SampleSH(vec3(0.0)) * _BaseColor.rgb * 0.3;
                return vec4(MixFog(color, fogFactor), 1.0);
            }
            void main() { fragColor = frag(); }
            #endif
            ENDGLSL
        }

        //#region outlinepass
        Pass
        {
            Name "Outline"
            // URP 的不透明队列会画 UniversalForward 和 SRPDefaultUnlit 两种 LightMode，
            // 所以第二个 Pass 用 SRPDefaultUnlit 就能自动被画到，不需要 Renderer Feature
            Tags { "LightMode"="SRPDefaultUnlit" }
            Cull Front      // 只画背面
            ZWrite On

            GLSLPROGRAM
            #pragma shader_feature_local_vertex _OUTLINESPACE_OBJECT _OUTLINESPACE_CLIP
            #pragma shader_feature_local_vertex _OUTLINENORMAL_MESH _OUTLINENORMAL_TANGENT _OUTLINENORMAL_VERTEXCOLOR
            #include "Ch14/ToonCommon.glsl"

            VARYING float fogFactor;

            #ifdef VERTEX
            // 取“用来外扩的法线”：原始法线 / 烘焙在切线里的平滑法线 / 烘焙在顶点色里的切线空间平滑法线
            vec3 GetOutlineNormalOS()
            {
            #if defined(_OUTLINENORMAL_TANGENT)
                return tangentOS.xyz;                               // 物体空间平滑法线
            #elif defined(_OUTLINENORMAL_VERTEXCOLOR)
                vec3 nTS = color.rgb * 2.0 - 1.0;                    // 切线空间平滑法线
                vec3 bitangentOS = cross(normalOS, tangentOS.xyz) * tangentOS.w;
                return normalize(nTS.x * tangentOS.xyz + nTS.y * bitangentOS + nTS.z * normalOS);
            #else
                return normalOS;
            #endif
            }

            void main()
            {
                vec3 n = GetOutlineNormalOS();
            #if defined(_OUTLINESPACE_OBJECT)
                gl_Position = OutlinePositionCS_ObjectSpace(positionOS.xyz, n, _OutlineWidthOS);
            #else
                gl_Position = OutlinePositionCS(positionOS.xyz, n, _OutlineWidth);
            #endif
                fogFactor = ComputeFogFactor(gl_Position.z);
            }
            #endif

            #ifdef FRAGMENT
            void main() { fragColor = vec4(MixFog(_OutlineColor.rgb, fogFactor), 1.0); }
            #endif
            ENDGLSL
        }
        //#endregion

        UsePass "Cookbook/Common/SHADOWCASTER"
        UsePass "Cookbook/Common/DEPTHONLY"
        UsePass "Cookbook/Common/DEPTHNORMALS"
    }
}
