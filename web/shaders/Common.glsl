// 各个 Shader 共用的 Pass：投影（ShadowCaster）、深度（DepthOnly）、深度法线（DepthNormals）。
// 用法：在 SubShader 里写 UsePass "Cookbook/Common/SHADOWCASTER"
// 第一个 Pass 是“找不到 Shader”时显示的洋红色（和 Unity 一样）。
Shader "Cookbook/Common"
{
    SubShader
    {
        Pass
        {
            Name "Error"
            Tags { "LightMode"="UniversalForward" }
            GLSLPROGRAM
            #ifdef VERTEX
            void main() { gl_Position = TransformObjectToHClip(positionOS.xyz); }
            #endif
            #ifdef FRAGMENT
            void main() { fragColor = vec4(1.0, 0.0, 1.0, 1.0); }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0
            GLSLPROGRAM
            #ifdef VERTEX
            void main() { gl_Position = GetShadowPositionHClip(positionOS.xyz, normalOS); }
            #endif
            #ifdef FRAGMENT
            void main() { fragColor = vec4(0.0); }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            GLSLPROGRAM
            #ifdef VERTEX
            void main() { gl_Position = TransformObjectToHClip(positionOS.xyz); }
            #endif
            #ifdef FRAGMENT
            void main() { fragColor = vec4(gl_FragCoord.z); }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode"="DepthNormals" }
            ZWrite On
            GLSLPROGRAM
            VARYING vec3 normalWS;
            #ifdef VERTEX
            void main()
            {
                gl_Position = TransformObjectToHClip(positionOS.xyz);
                normalWS = TransformObjectToWorldNormal(normalOS);
            }
            #endif
            #ifdef FRAGMENT
            void main() { fragColor = vec4(normalize(normalWS), 0.0); }
            #endif
            ENDGLSL
        }
    }
}
