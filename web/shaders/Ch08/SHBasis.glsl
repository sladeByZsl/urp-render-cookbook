// 可视化前三阶（l = 0,1,2）实数球谐基函数 Y_lm。（GLSL 版，对应 Ch08/SHBasis.shader）
// 模式 0：在单位球面上着色；模式 1：把球面顶点沿径向推到 |Y_lm| 处，得到经典的“花瓣”形状。
// 暖色 = 正值，冷色 = 负值。
Shader "Cookbook/Ch08/SHBasis"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform vec4  _PosColor;
        uniform vec4  _NegColor;
        uniform float _L;
        uniform float _M;
        uniform float _Mode;
        uniform float _Scale;

        //#region basis
        // 实数球谐基函数，系数与 core 的 SphericalHarmonics.hlsl 中 kSHBasis0~4 一致。
        // d 为单位方向；Unity 的 SphericalHarmonicsL2 也按这 9 个函数、这个顺序存系数。
        float SHBasis(int l, int m, vec3 d)
        {
            float x = d.x, y = d.y, z = d.z;
            if (l == 0) return 0.282095;                                   // Y00 = 1/2·sqrt(1/π)
            if (l == 1)
            {
                if (m == -1) return 0.488603 * y;                          // Y1-1
                if (m == 0)  return 0.488603 * z;                          // Y10
                return 0.488603 * x;                                       // Y11
            }
            if (m == -2) return 1.092548 * x * y;                          // Y2-2
            if (m == -1) return 1.092548 * y * z;                          // Y2-1
            if (m == 0)  return 0.315392 * (3.0 * z * z - 1.0);            // Y20
            if (m == 1)  return 1.092548 * x * z;                          // Y21
            return 0.546274 * (x * x - y * y);                             // Y22
        }
        //#endregion
        ENDGLSL

        Pass
        {
            Name "Unlit"
            Tags { "LightMode"="UniversalForwardOnly" }
            GLSLPROGRAM
            VARYING vec3 positionWS;
            VARYING float value;

            #ifdef VERTEX
            void main()
            {
                vec3 dir = normalize(positionOS.xyz);
                float y = SHBasis(int(round(_L)), int(round(_M)), dir);
                vec3 p = _Mode > 0.5 ? dir * abs(y) * _Scale : positionOS.xyz;
                positionWS = TransformObjectToWorld(p);
                gl_Position = TransformWorldToHClip(positionWS);
                value = y;
            }
            #endif

            #ifdef FRAGMENT
            void main()
            {
                // 变形后的网格没有正确法线，用屏幕导数求面法线，做一点简单明暗
                // （HLSL 的 ddy/ddx 对应 dFdy/dFdx；WebGL 屏幕 y 不翻转，叉乘顺序相反，下面的 dot 判断会把朝向纠正过来）
                vec3 n = normalize(cross(dFdy(positionWS), dFdx(positionWS)));
                vec3 v = GetWorldSpaceNormalizeViewDir(positionWS);
                if (dot(n, v) < 0.0) n = -n;
                vec3 l = normalize(vec3(-0.4, 0.8, -0.6));
                float shade = 0.35 + 0.65 * saturate(dot(n, l));
                vec3 c = value >= 0.0 ? _PosColor.rgb : _NegColor.rgb;
                if (_Mode < 0.5) c *= saturate(abs(value) * 2.0) * 0.85 + 0.15;   // 球面模式：亮度 = |Y|
                fragColor = vec4(c * shade, 1.0);
            }
            #endif
            ENDGLSL
        }
    }
}
