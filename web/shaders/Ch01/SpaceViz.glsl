// 第 1 章 案例 1.1：坐标空间可视化
// 同一个顶点，在不同空间里坐标不同。这个调试 Shader 把各空间的坐标“涂”在物体表面，
// 用 _Mode 切换：物体空间 / 世界空间 / 观察空间 / NDC / 裁剪空间 w / 屏幕像素坐标。
Shader "Cookbook/Ch01/SpaceViz"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        Pass
        {
            Name "SpaceViz"
            Tags { "LightMode"="UniversalForward" }

            GLSLPROGRAM
            uniform float _Mode;
            uniform float _GridSize;
            uniform float _DepthScale;
            uniform float _PixelCell;

            //#region varyings
            // 交给光栅化器的裁剪空间坐标写进 gl_Position（到了片元里会变成像素坐标 gl_FragCoord）
            VARYING vec3 vPositionOS;   // 物体空间
            VARYING vec3 vPositionWS;   // 世界空间
            VARYING vec3 vPositionVS;   // 观察空间（右手系，相机看向 -Z）
            VARYING vec4 vPositionHCS;  // 裁剪空间的一份拷贝：gl_FragCoord 在片元阶段已被改写，想要原值得自己传

            #ifdef VERTEX
            void main()
            {
                // URP 一次性算好各个空间的位置（ShaderVariablesFunctions.hlsl）
                VertexPositionInputs pos = GetVertexPositionInputs(positionOS.xyz);
                gl_Position  = pos.positionCS;
                vPositionOS  = positionOS.xyz;
                vPositionWS  = pos.positionWS;
                vPositionVS  = pos.positionVS;
                vPositionHCS = pos.positionCS;
            }
            #endif
            //#endregion

            #ifdef FRAGMENT
            // 抗锯齿网格线：p 落在 size 的整数倍附近时返回 1。
            // fwidth 给出 p 在相邻像素间的变化量，用它做线宽，线在远处也保持约 1 像素宽。
            // 在某个表面上恒定不变的分量（如地面的 y）fwidth 为 0，要排除，否则整面都会被当成“线上”。
            float GridLine(vec3 p, float size)
            {
                vec3 q = p / size;
                vec3 fw = fwidth(q);
                vec3 d = abs(fract(q - 0.5) - 0.5) / max(fw, vec3(1e-5));
                d += step(fw, vec3(1e-6)) * 1e6;
                return 1.0 - saturate(min(min(d.x, d.y), d.z) - 0.5);
            }

            float GridLine2(vec2 p, float size)
            {
                vec2 q = p / size;
                vec2 d = abs(fract(q - 0.5) - 0.5) / max(fwidth(q), vec2(1e-5));
                return 1.0 - saturate(min(d.x, d.y) - 0.5);
            }

            //#region frag
            void main()
            {
                vec3 col = vec3(0.0);
                int mode = int(_Mode);

                if (mode == 0)          // 物体空间：坐标跟着物体走，旋转缩放物体，图案跟着转
                {
                    col = saturate(vPositionOS + 0.5);
                    col = mix(col, vec3(0.05), GridLine(vPositionOS, 0.25 * _GridSize));
                }
                else if (mode == 1)     // 世界空间：所有物体共用一套坐标，网格线在物体之间连续
                {
                    vec3 cell = fract(vPositionWS / _GridSize);
                    col = 0.25 + 0.6 * cell;
                    col = mix(col, vec3(0.05), GridLine(vPositionWS, _GridSize));
                    // 世界原点处的 X 轴（红）、Z 轴（蓝）
                    float ax = 1.0 - saturate(abs(vPositionWS.z) / (2.0 * fwidth(vPositionWS.z)));
                    float az = 1.0 - saturate(abs(vPositionWS.x) / (2.0 * fwidth(vPositionWS.x)));
                    col = mix(col, vec3(1, 0.1, 0.1), ax);
                    col = mix(col, vec3(0.1, 0.3, 1), az);
                }
                else if (mode == 2)     // 观察空间：x 向右、y 向上，深度 = -z
                {
                    float depth = -vPositionVS.z;
                    col.rg = saturate(vPositionVS.xy * 0.25 + 0.5);
                    col.b  = saturate(depth / _DepthScale);
                    // 等深线：每 1 米一条，它们都与相机的成像平面平行
                    float iso = abs(fract(depth - 0.5) - 0.5) / max(fwidth(depth), 1e-5);
                    col = mix(col, vec3(1.0), 1.0 - saturate(iso - 0.5));
                }
                else if (mode == 3)     // NDC：透视除法之后，可见范围 x、y 都在 [-1, 1]
                {
                    vec2 ndc = vPositionHCS.xy / vPositionHCS.w;
                    ndc.y *= _ProjectionParams.x;      // 渲染到 RT 时投影矩阵被上下翻转过，这里翻回来，让 +y 永远朝上（WebGL 里恒为 1）
                    col = vec3(saturate(ndc.x), saturate(ndc.y), saturate(-ndc.x) * 0.7 + saturate(-ndc.y) * 0.3);
                    col = mix(col, vec3(0.0), GridLine2(ndc, 0.25));
                    col = mix(col, vec3(1.0), GridLine2(ndc, 1.0));   // 中心十字（x=0、y=0）
                }
                else if (mode == 4)     // 裁剪空间的 w：透视投影下它就是观察空间深度
                {
                    float w = vPositionHCS.w;
                    col = vec3(saturate(w / _DepthScale));
                    float iso = abs(fract(w - 0.5) - 0.5) / max(fwidth(w), 1e-5);
                    col = mix(col, vec3(1, 0.45, 0.2), 1.0 - saturate(iso - 0.5));
                }
                else                    // 片元阶段的 gl_FragCoord.xy：像素中心坐标（如 100.5, 37.5）
                {
                    // 注意：Unity（D3D）的像素坐标原点在左上角，WebGL 在左下角，棋盘格的起点会差半格
                    vec2 cell = floor(gl_FragCoord.xy / _PixelCell);
                    float s = cell.x + cell.y;
                    float k = s - 2.0 * trunc(s / 2.0);    // fmod(s, 2)
                    col = mix(vec3(0.9, 0.9, 0.92), vec3(0.25, 0.45, 0.6), k);
                }
                fragColor = vec4(col, 1);
            }
            //#endregion
            #endif
            ENDGLSL
        }
    }
}
