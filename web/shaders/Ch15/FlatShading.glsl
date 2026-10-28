// 低多边形（Low Poly）flat shading：不改网格，在片元里用 ddx/ddy 求三角形的面法线。（GLSL 版，对应 Ch15/FlatShading.shader）
// 演示场景是一块在顶点着色器里用噪声抬高的地形，可以在“平滑法线 / 面法线”之间切换。
Shader "Cookbook/Ch15/FlatShading"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform vec4 _BaseColor;
        uniform float _Flat, _Terrain, _HeightScale, _NoiseTiling, _WaterLevel;
        uniform sampler2D _HeightTex;

        // 地形高度：世界 xz 采样噪声。顶点着色器里必须用 LOD 版本采样（没有导数可用）
        float TerrainHeight(vec2 xz)
        {
            float h = textureLod(_HeightTex, xz * _NoiseTiling, 0.0).r;
            h = (h - 0.45) * _HeightScale * 2.0;
            return max(h, _WaterLevel);     // 低于水位的部分压平成水面
        }

        // 所有 Pass 共用的顶点变形：地形模式下抬高顶点，并用有限差分算出平滑法线
        void Deform(inout vec3 posWS, inout vec3 nrmWS)
        {
            if (_Terrain < 0.5) return;
            const float e = 0.05;
            float h  = TerrainHeight(posWS.xz);
            float hx = TerrainHeight(posWS.xz + vec2(e, 0));
            float hz = TerrainHeight(posWS.xz + vec2(0, e));
            posWS.y += h;
            nrmWS = normalize(vec3(h - hx, e, h - hz));
        }
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            GLSLPROGRAM
            #define NPR_VARYINGS
            #include "Ch15/NPRCommon.glsl"

            #ifdef VERTEX
            void main()
            {
                vec3 posWS = TransformObjectToWorld(positionOS.xyz);
                vec3 nrmWS = TransformObjectToWorldNormal(normalOS);
                Deform(posWS, nrmWS);
                positionWS = posWS;
                normalWS = nrmWS;
                gl_Position = TransformWorldToHClip(posWS);
                uv = texcoord0.xy; vertexColor = color; fogFactor = 0.0;
            }
            #endif

            #ifdef FRAGMENT
            //#region facenormal
            vec3 FaceNormal(vec3 posWS)
            {
                // ddx/ddy：相邻像素之间世界坐标的差，两者都躺在三角形平面内，叉乘就是面法线。
                // 同一个 2×2 像素块里共享导数，而三角形内部世界坐标是线性的，所以结果是“整面常量”。
                vec3 n = normalize(cross(dFdy(posWS), dFdx(posWS)));
                // 屏幕 y 轴朝上还是朝下因平台/是否渲染到 RT 而异，叉乘方向可能反过来；
                // 正面一定朝向相机，所以用视线方向把它翻正，最省心
                vec3 V = _WorldSpaceCameraPos - posWS;
                return dot(n, V) < 0.0 ? -n : n;
            }
            //#endregion

            vec3 TerrainColor(float y, vec3 N)
            {
                vec3 c = vec3(0.10, 0.32, 0.62);                                           // 水
                c = mix(c, vec3(0.80, 0.68, 0.42), step(_WaterLevel + 0.02, y));           // 沙
                c = mix(c, vec3(0.30, 0.55, 0.18), step(_WaterLevel + 0.25, y));           // 草
                c = mix(c, vec3(0.42, 0.37, 0.33), step(0.3, y) * step(N.y, 0.9));        // 陡坡变岩石
                c = mix(c, vec3(0.92, 0.93, 0.96), step(1.3, y));                          // 雪
                // 上面这些常量是按“显示器上看到的颜色”（sRGB）挑的，线性空间工程里要先转成线性值
                return SRGBToLinear(c);
            }

            vec4 frag()
            {
                vec3 N = _Flat > 0.5 ? FaceNormal(positionWS) : normalize(normalWS);
                NprLight L = GetNprLight(positionWS, N);
                vec3 albedo = _Terrain > 0.5 ? TerrainColor(positionWS.y, N) : _BaseColor.rgb;
                vec3 col = albedo * (saturate(L.ndotl) * L.shadow * L.color + SampleSH(N));
                return vec4(col, 1.0);
            }
            void main() { fragColor = frag(); }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0
            GLSLPROGRAM
            #include "Ch15/NPRCommon.glsl"
            #ifdef VERTEX
            void main()
            {
                vec3 posWS = TransformObjectToWorld(positionOS.xyz);
                vec3 nrmWS = TransformObjectToWorldNormal(normalOS);
                Deform(posWS, nrmWS);   // 阴影要和颜色 Pass 用同样的变形
                vec4 positionCS = TransformWorldToHClip(ApplyShadowBias(posWS, nrmWS, _LightDirection));
                positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE * positionCS.w);   // WebGL 不反转深度
                gl_Position = positionCS;
            }
            #endif
            #ifdef FRAGMENT
            void main() { fragColor = NprNullFrag(); }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            GLSLPROGRAM
            #include "Ch15/NPRCommon.glsl"
            #ifdef VERTEX
            void main()
            {
                vec3 posWS = TransformObjectToWorld(positionOS.xyz);
                vec3 nrmWS = TransformObjectToWorldNormal(normalOS);
                Deform(posWS, nrmWS);
                gl_Position = TransformWorldToHClip(posWS);
            }
            #endif
            #ifdef FRAGMENT
            void main() { fragColor = vec4(gl_FragCoord.z); }
            #endif
            ENDGLSL
        }
    }
}
