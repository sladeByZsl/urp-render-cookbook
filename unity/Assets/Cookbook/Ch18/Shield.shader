// 案例 18.6~18.7：能量护盾。深度交接高亮 + 六边形网格 + 菲涅尔 + 受击涟漪。
// 透明队列读取 _CameraDepthTexture（URP Asset 需开启 Depth Texture）。
Shader "Cookbook/Ch18/Shield"
{
    Properties
    {
        [HDR] _ShieldColor ("Shield Color", Color) = (0.2,0.7,1.6,1)
        _BaseAlpha ("Base Intensity", Range(0,1)) = 0.04
        _RimPower ("Rim Power", Range(0.5,8)) = 3
        [Header(Intersection)]
        _IntersectWidth ("Intersect Width (m)", Range(0,1)) = 0.25
        _IntersectStrength ("Intersect Strength", Range(0,8)) = 3
        [Header(Hexagon)]
        _HexScale ("Hex Count (around)", Float) = 16
        _HexLine ("Hex Line Width", Range(0.005,0.2)) = 0.05
        _HexStrength ("Hex Strength", Range(0,2)) = 0.6
        [Header(Hit)]
        _HitPos ("Hit Position (World)", Vector) = (0,1,-2,0)
        _HitProgress ("Hit Progress", Range(0,1)) = 0
        _HitRadius ("Hit Max Radius (m)", Float) = 2.5
        _HitStrength ("Hit Strength", Range(0,10)) = 4
        _HitDisplace ("Hit Displacement (m)", Range(0,0.3)) = 0.06
        [Header(Time)]
        [Toggle] _AutoPlay ("Auto Play (_Time)", Float) = 0
        _Phase ("Phase (seconds)", Float) = 0
    }

    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent" "RenderPipeline"="UniversalPipeline" }

        Pass
        {
            Name "Shield"
            Tags { "LightMode"="UniversalForward" }
            Blend One One
            ZWrite Off
            Cull Off            // 双面：从外面也能看到球的内壁，更有“罩子”的体积感

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Assets/Cookbook/Ch18/Ch18Common.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            CBUFFER_START(UnityPerMaterial)
                half4  _ShieldColor;
                half   _BaseAlpha;
                half   _RimPower;
                half   _IntersectWidth;
                half   _IntersectStrength;
                float  _HexScale;
                half   _HexLine;
                half   _HexStrength;
                float4 _HitPos;
                half   _HitProgress;
                float  _HitRadius;
                half   _HitStrength;
                half   _HitDisplace;
                half   _AutoPlay;
                float  _Phase;
            CBUFFER_END

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; float2 uv : TEXCOORD0; };
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                half3  normalWS   : TEXCOORD1;
                float2 uv         : TEXCOORD2;
                float  eyeDepth   : TEXCOORD3;   // 本片元到相机的观察空间深度（米）
                half   poleFade   : TEXCOORD4;
            };

            float ShieldTime() { return _AutoPlay > 0.5 ? _Time.y : _Phase; }

            //#region hit
            // 受击涟漪：以命中点为圆心向外扩散的一圈环，越往外越淡
            half HitRing(float3 positionWS)
            {
                float d = distance(positionWS, _HitPos.xyz);
                float r = _HitProgress * _HitRadius;
                float width = 0.12 + 0.25 * _HitProgress;
                half ring = saturate(1.0 - abs(d - r) / width);
                half fade = (1.0 - _HitProgress) * step(0.001, _HitProgress);
                // 命中点本身还有一个快速消退的亮斑
                half spot = saturate(1.0 - d / (0.4 + r * 0.3)) * (1.0 - _HitProgress) * (1.0 - _HitProgress);
                return (ring * ring + spot) * fade;
            }
            //#endregion

            Varyings vert(Attributes v)
            {
                Varyings o;
                float3 positionWS = TransformObjectToWorld(v.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(v.normalOS);
                // 涟漪经过的地方顶点沿法线鼓起一点点
                positionWS += normalWS * HitRing(positionWS) * _HitDisplace;
                o.positionWS = positionWS;
                o.positionCS = TransformWorldToHClip(positionWS);
                o.normalWS = normalWS;
                o.uv = v.uv;
                o.eyeDepth = -TransformWorldToView(positionWS).z;   // 观察空间看向 -Z，取负得正的深度
                o.poleFade = 1.0 - pow(abs(v.normalOS.y), 6.0);      // 球面 UV 在两极挤成一点，六边形淡出
                return o;
            }

            //#region hex
            // 六边形网格：返回到最近六边形中心的局部坐标(xy)与格子 id(zw)
            float4 HexGrid(float2 p)
            {
                const float2 s = float2(1.0, 1.7320508);           // (1, √3)
                float4 c = floor(float4(p, p - float2(0.5, 1.0)) / s.xyxy) + 0.5;
                float4 h = float4(p - c.xy * s, p - (c.zw + 0.5) * s);
                return dot(h.xy, h.xy) < dot(h.zw, h.zw) ? float4(h.xy, c.xy) : float4(h.zw, c.zw + 0.5);
            }

            // 六边形的“距离”：中心为 0，边上为 0.5
            float HexDist(float2 p)
            {
                p = abs(p);
                return max(dot(p, float2(0.5, 0.8660254)), p.x);
            }
            //#endregion

            //#region frag
            half4 frag(Varyings i, FRONT_FACE_TYPE face : FRONT_FACE_SEMANTIC) : SV_Target
            {
                float t = ShieldTime();
                half3 normalWS = normalize(i.normalWS) * IS_FRONT_VFACE(face, 1.0h, -1.0h);
                half3 viewWS = GetWorldSpaceNormalizeViewDir(i.positionWS);

                // 1) 深度交接：场景深度 - 自身深度 越小，说明越贴近别的物体表面
                float2 screenUV = GetNormalizedScreenSpaceUV(i.positionCS);
                float sceneEye = LinearEyeDepth(SampleSceneDepth(screenUV), _ZBufferParams);
                float gap = sceneEye - i.eyeDepth;
                half intersect = 1.0h - saturate(gap / max(_IntersectWidth, 1e-4h));
                intersect = intersect * intersect * _IntersectStrength;

                // 2) 菲涅尔轮廓（背面也算，球的内壁边缘同样会亮）
                half rim = FresnelRim(normalWS, viewWS, _RimPower);

                // 3) 六边形：球面 U 绕一圈（2πR），V 从南极到北极（πR），
                //    所以 V 方向只铺 U 的一半，格子才不被拉伸；_HexScale 取整数，U 的接缝处就能无缝衔接
                float2 hp = i.uv * float2(_HexScale, _HexScale * 0.5);
                float4 hex = HexGrid(hp);
                half edge = smoothstep(0.5 - _HexLine, 0.5, HexDist(hex.xy));
                // 每个格子一个随机相位，缓慢呼吸明暗
                half cellPulse = 0.5 + 0.5 * sin(t * 2.0 + Hash21(hex.zw) * 6.2831);
                half hexMask = (edge + cellPulse * 0.15h) * _HexStrength * i.poleFade;

                // 4) 受击：环经过的地方六边形整体点亮
                half hit = HitRing(i.positionWS);
                half hitHex = hit * (0.35h + edge) * _HitStrength;

                half back = IS_FRONT_VFACE(face, 1.0h, 0.45h);    // 内壁暗一些，前后有层次
                half intensity = (_BaseAlpha + rim + hexMask * (0.3h + rim)) * back + intersect + hitHex;
                return half4(_ShieldColor.rgb * intensity, 1);
            }
            //#endregion
            ENDHLSL
        }
    }
}
