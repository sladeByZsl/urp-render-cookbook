// Unity 内置的 Skybox/Cubemap 着色器的 GLSL 版本
Shader "Skybox/Cubemap"
{
    SubShader
    {
        Tags { "Queue"="Background" }
        Cull Off ZWrite Off
        Pass
        {
            GLSLPROGRAM
            uniform samplerCube _Tex;
            uniform vec4 _Tint;
            uniform float _Exposure;
            uniform float _Rotation;
            VARYING vec3 texcoord;
            #ifdef VERTEX
            void main()
            {
                // 绕 y 轴旋转天空，然后只用相机的旋转（去掉平移），把深度推到最远处
                float a = radians(_Rotation);
                float s = sin(a), c = cos(a);
                vec3 p = vec3(c * positionOS.x - s * positionOS.z, positionOS.y, s * positionOS.x + c * positionOS.z);
                vec4 viewPos = vec4(mat3(unity_MatrixV) * p, 1.0);
                vec4 clip = unity_MatrixP * vec4(viewPos.xyz, 1.0);
                gl_Position = clip.xyww;
                texcoord = positionOS.xyz;
            }
            #endif
            #ifdef FRAGMENT
            void main()
            {
                vec3 c = texture(_Tex, texcoord).rgb;
                // unity_ColorSpaceDouble 在线性空间下是 4.59479（= 2^2.2），与默认 _Tint(0.5 灰) 相乘约为 1
                c = c * _Tint.rgb * 4.59479380 * _Exposure;
                fragColor = vec4(c, 1.0);
            }
            #endif
            ENDGLSL
        }
    }
}
