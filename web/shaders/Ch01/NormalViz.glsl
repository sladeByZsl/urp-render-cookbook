// 第 1 章 案例 1.2：法线可视化，以及“非均匀缩放下法线该怎么变换”
// _Mode：0 物体空间法线 / 1 世界空间法线 / 2 观察空间法线
//        3 用正确的世界法线做 Lambert / 4 用错误的方式（直接乘模型矩阵）变换法线做 Lambert
//        5 两种法线算出的光照之差（放大 4 倍）
Shader "Cookbook/Ch01/NormalViz"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        Pass
        {
            Name "NormalViz"
            Tags { "LightMode"="UniversalForward" }

            GLSLPROGRAM
            uniform float _Mode;
            uniform vec4 _BaseColor;

            VARYING vec3 vNormalOS;
            VARYING vec3 vNormalWS;
            VARYING vec3 vNormalWSWrong;
            VARYING vec3 vNormalVS;

            //#region vert
            #ifdef VERTEX
            void main()
            {
                gl_Position = TransformObjectToHClip(positionOS.xyz);
                vNormalOS   = normalOS;

                // 正确：乘“模型矩阵的逆转置”。URP 的实现是 mul(normalOS, (float3x3)WorldToObject)，
                // 行向量左乘逆矩阵，等价于列向量左乘逆矩阵的转置（SpaceTransforms.hlsl）
                vNormalWS = TransformObjectToWorldNormal(normalOS);

                // 错误：把法线当成普通方向，直接乘模型矩阵。均匀缩放时没问题，非均匀缩放时法线不再垂直于表面
                vNormalWSWrong = TransformObjectToWorldDir(normalOS);

                // 观察空间法线：方向只受旋转影响，用 3x3 的观察矩阵即可（相机矩阵不含缩放）
                vNormalVS = TransformWorldToViewDir(vNormalWS);
            }
            #endif
            //#endregion

            #ifdef FRAGMENT
            vec3 Lambert(vec3 n)
            {
                Light light = GetMainLight();
                float ndl = saturate(dot(n, light.direction));
                return _BaseColor.rgb * (light.color * ndl + 0.08);
            }

            //#region frag
            void main()
            {
                // 插值后的法线长度会小于 1，必须重新归一化
                vec3 nOS = normalize(vNormalOS);
                vec3 nWS = normalize(vNormalWS);
                vec3 nWrong = normalize(vNormalWSWrong);
                vec3 nVS = normalize(vNormalVS);

                int mode = int(_Mode);
                vec3 col;
                if (mode == 0)      col = nOS * 0.5 + 0.5;   // [-1,1] 映射到 [0,1] 才能当颜色看
                else if (mode == 1) col = nWS * 0.5 + 0.5;
                else if (mode == 2) col = nVS * 0.5 + 0.5;
                else if (mode == 3) col = Lambert(nWS);
                else if (mode == 4) col = Lambert(nWrong);
                else                col = abs(Lambert(nWS) - Lambert(nWrong)) * 4.0;
                fragColor = vec4(col, 1);
            }
            //#endregion
            #endif
            ENDGLSL
        }
    }
}
