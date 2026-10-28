// Matcap（材质捕获）：把“一颗已经打好光的球”的照片，按观察空间法线贴到物体上。（GLSL 版，对应 Ch08/Matcap.shader）
// 作为环境光照的对照：它便宜、好调，但光照永远跟着相机走，与场景无关。
Shader "Cookbook/Ch08/Matcap"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform vec4  _Tint;
        uniform float _PerspectiveFix;
        ENDGLSL

        Pass
        {
            Name "Unlit"
            Tags { "LightMode"="UniversalForwardOnly" }
            GLSLPROGRAM
            uniform sampler2D _MatCap;

            VARYING vec3 normalVS;
            VARYING vec3 positionVS;

            #ifdef VERTEX
            void main()
            {
                vec3 positionWS = TransformObjectToWorld(positionOS.xyz);
                gl_Position = TransformWorldToHClip(positionWS);
                positionVS = TransformWorldToView(positionWS);
                normalVS = TransformWorldToViewDir(TransformObjectToWorldNormal(normalOS));
            }
            #endif

            #ifdef FRAGMENT
            //#region matcap
            void main()
            {
                vec3 n = normalize(normalVS);
                vec2 uv;
                if (_PerspectiveFix > 0.5)
                {
                    // 透视修正：用“视线方向”构造一个局部坐标系，再把法线投影进去。
                    // 否则物体在画面边缘时，Matcap 会被明显拉扯（只有正交相机下 n.xy 才是准确的）
                    vec3 v = normalize(positionVS);          // 观察空间里从相机指向表面
                    vec3 r = cross(v, n);
                    uv = vec2(-r.y, r.x);
                }
                else
                {
                    uv = n.xy;                               // 经典写法：直接取观察空间法线的 xy
                }
                uv = uv * 0.5 + 0.5;
                vec3 c = texture(_MatCap, uv).rgb * _Tint.rgb;
                fragColor = vec4(c, 1.0);
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
