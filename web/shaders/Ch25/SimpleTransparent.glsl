// 对照用：最普通的逐物体半透明（简单漫反射 + Alpha 混合，不写深度）。
// 案例 25.2 用它当“玻璃”，案例 25.7 用它展示“逐物体半透明会露出内部结构”的问题。
Shader "Cookbook/Ch25/SimpleTransparent"
{
    SubShader
    {
        Tags { "RenderType"="Transparent" "RenderPipeline"="UniversalPipeline" "Queue"="Transparent" }
        Pass
        {
            Name "Forward"
            Tags { "LightMode"="UniversalForward" }
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off

            GLSLPROGRAM
            uniform vec4 _BaseColor;

            VARYING vec3 normalWS;

            #ifdef VERTEX
            void main()
            {
                gl_Position = TransformObjectToHClip(positionOS.xyz);
                normalWS = TransformObjectToWorldNormal(normalOS);
            }
            #endif

            #ifdef FRAGMENT
            void main()
            {
                Light light = GetMainLight();
                float ndl = saturate(dot(normalize(normalWS), light.direction)) * 0.7 + 0.3;
                fragColor = vec4(_BaseColor.rgb * light.color * ndl, _BaseColor.a);
            }
            #endif
            ENDGLSL
        }
    }
}
