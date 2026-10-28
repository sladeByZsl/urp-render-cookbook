// 不用法线贴图，直接从高度图算法线：①中心差分（多采样 4 次）②屏幕导数 dFdx/dFdy（只采样 1 次）。（GLSL 版，对应 Ch07/HeightToNormal.shader）
// 模式 0 是烘焙好的法线贴图，作为参照。
Shader "Cookbook/Ch07/HeightToNormal"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform vec4  _BaseMap_ST;
        uniform vec4  _HeightMap_TexelSize;   // 引擎自动填充：(1/宽, 1/高, 宽, 高)
        uniform float _HeightStrength;
        uniform float _Mode;
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            GLSLPROGRAM
            #include "Ch07/Ch07Common.glsl"

            uniform sampler2D _BaseMap;
            uniform sampler2D _BumpMap;
            uniform sampler2D _HeightMap;

            VARYING vec2 uv;
            VARYING vec3 positionWS;
            VARYING vec3 normalWS;
            VARYING vec4 tangentWS;

            #ifdef VERTEX
            void main()
            {
                VertexPositionInputs pos = GetVertexPositionInputs(positionOS.xyz);
                VertexNormalInputs nrm = GetVertexNormalInputs(normalOS, tangentOS);
                gl_Position = pos.positionCS;
                positionWS = pos.positionWS;
                uv = TransformTex(texcoord0.xy, _BaseMap_ST);
                normalWS = nrm.normalWS;
                tangentWS = vec4(nrm.tangentWS, tangentOS.w * GetOddNegativeScale());
            }
            #endif

            #ifdef FRAGMENT
            float SampleHeight(vec2 uv) { return texture(_HeightMap, uv).r; }

            //#region central
            // 中心差分：在 U、V 方向各取左右两个邻居。结果与离线烘焙法线贴图的算法一致。
            vec3 NormalFromHeightCentral(vec2 uv)
            {
                vec2 t = _HeightMap_TexelSize.xy;
                float hL = SampleHeight(uv - vec2(t.x, 0));
                float hR = SampleHeight(uv + vec2(t.x, 0));
                float hD = SampleHeight(uv - vec2(0, t.y));
                float hU = SampleHeight(uv + vec2(0, t.y));
                // 每个纹素的高度差 × 强度 = 斜率；法线 = normalize(-dh/du, -dh/dv, 1)
                float dhdu = (hR - hL) * 0.5 * _HeightStrength;
                float dhdv = (hU - hD) * 0.5 * _HeightStrength;
                return normalize(vec3(-dhdu, -dhdv, 1));
            }
            //#endregion

            //#region derivative
            // 屏幕导数：dFdx/dFdy 给出“相邻像素之间”h 和 uv 的变化量，解一个 2×2 线性方程
            // 就能把屏幕空间的变化换算成 dh/du、dh/dv。只采样一次，但精度受 2×2 像素块限制。
            vec3 NormalFromHeightDerivative(vec2 uv)
            {
                float h = SampleHeight(uv);
                vec2 duvdx = dFdx(uv), duvdy = dFdy(uv);
                float dhdx = dFdx(h), dhdy = dFdy(h);
                // [duvdx; duvdy] · (dh/du, dh/dv) = (dhdx, dhdy)，用克拉默法则求解
                float det = duvdx.x * duvdy.y - duvdx.y * duvdy.x;
                vec2 grad = vec2(dhdx * duvdy.y - dhdy * duvdx.y,
                                 duvdx.x * dhdy - duvdy.x * dhdx) / (abs(det) > 1e-12 ? det : 1e-12);
                grad *= _HeightMap_TexelSize.xy * _HeightStrength;   // 每 UV 单位 → 每纹素
                return normalize(vec3(-grad, 1));
            }
            //#endregion

            void main()
            {
                vec3 normalTS;
                if (_Mode < 0.5)      normalTS = UnpackNormal(texture(_BumpMap, uv));
                else if (_Mode < 1.5) normalTS = NormalFromHeightCentral(uv);
                else                  normalTS = NormalFromHeightDerivative(uv);

                vec3 bitangent = tangentWS.w * cross(normalWS, tangentWS.xyz);
                vec3 nWS = NormalizeNormalPerPixel(
                    TransformTangentToWorld(normalTS, mat3(tangentWS.xyz, bitangent, normalWS)));
                vec3 albedo = texture(_BaseMap, uv).rgb;
                fragColor = vec4(Ch07Shade(positionWS, nWS, albedo, 0.45, 0.15, 1.0), 1.0);
            }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0
            GLSLPROGRAM
            #define CH07_SHADOW_PASS
            #include "Ch07/Ch07Common.glsl"
            ENDGLSL
        }
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            GLSLPROGRAM
            #define CH07_DEPTH_PASS
            #include "Ch07/Ch07Common.glsl"
            ENDGLSL
        }
    }
}
