// 案例 25.4：给 RenderObjects 当 Override Material 用的“叠加边缘光”。
// 物体已经在不透明 Pass 里画过一次，这里在同一深度上再画一遍，用加法混合叠上菲涅尔边缘光。
Shader "Cookbook/Ch25/RimOverlay"
{
    SubShader
    {
        Tags { "RenderType"="Transparent" "RenderPipeline"="UniversalPipeline" "Queue"="Transparent" }

        Pass
        {
            Name "RimOverlay"
            Tags { "LightMode"="SRPDefaultUnlit" }
            Blend One One          // 加法：只增亮，不遮盖原来的颜色
            ZWrite Off
            ZTest LEqual           // 与自己在不透明 Pass 写下的深度相等，能通过

            GLSLPROGRAM
            uniform vec4  _RimColor;
            uniform float _RimPower;
            uniform float _FillAlpha;

            VARYING vec3 normalWS;
            VARYING vec3 positionWS;

            #ifdef VERTEX
            void main()
            {
                VertexPositionInputs p = GetVertexPositionInputs(positionOS.xyz);
                gl_Position = p.positionCS;
                positionWS = p.positionWS;
                normalWS = TransformObjectToWorldNormal(normalOS);
            }
            #endif

            #ifdef FRAGMENT
            void main()
            {
                vec3 n = normalize(normalWS);
                vec3 v = GetWorldSpaceNormalizeViewDir(positionWS);
                float rim = pow(1.0 - saturate(dot(n, v)), _RimPower);
                fragColor = vec4(_RimColor.rgb * (rim + _FillAlpha), 1.0);
            }
            #endif
            ENDGLSL
        }
    }
}
