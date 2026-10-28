// 案例 21.2：序列帧动画（Flipbook）——按时间算帧号，可选帧间混合；附带图集调试视图
Shader "Cookbook/Ch21/Flipbook"
{
    Properties
    {
        [MainTexture] _BaseMap ("Flipbook Atlas", 2D) = "white" {}
        [HDR] _BaseColor ("Tint", Color) = (1,1,1,1)
        _Grid ("Columns(x) Rows(y)", Vector) = (4, 4, 0, 0)
        _FPS ("Frames Per Second", Float) = 12
        _Frame ("Frame Offset (for stills)", Float) = 0
        [Toggle(_FLIPBOOK_BLEND)] _Blend ("Blend Between Frames", Float) = 1
        [Toggle(_DEBUG_ATLAS)] _DebugAtlas ("Debug: Show Atlas", Float) = 0
    }
    SubShader
    {
        Tags { "RenderType"="Transparent" "RenderPipeline"="UniversalPipeline" "Queue"="Transparent" "IgnoreProjector"="True" }

        Pass
        {
            Name "Unlit"
            Tags { "LightMode"="UniversalForward" }
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            Cull Off
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma shader_feature_local_fragment _FLIPBOOK_BLEND
            #pragma shader_feature_local_fragment _DEBUG_ATLAS
            #pragma multi_compile_instancing
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Assets/Cookbook/Ch21/UVAnim.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                half4 _BaseColor;
                float4 _Grid;
                float _FPS, _Frame;
            CBUFFER_END
            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);

            struct Attributes { float4 positionOS : POSITION; float2 uv : TEXCOORD0; half4 color : COLOR; UNITY_VERTEX_INPUT_INSTANCE_ID };
            struct Varyings  { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; half4 color : COLOR; };

            Varyings vert(Attributes v)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                o.uv = v.uv;
                o.color = v.color;
                return o;
            }

            //#region frag
            half4 frag(Varyings i) : SV_Target
            {
                float frame = _Time.y * _FPS + _Frame;       // 连续的“帧号”，小数部分就是两帧之间的进度

            #if defined(_DEBUG_ATLAS)
                // 调试：整张图集 + 网格线；当前帧描橙框，下一帧描蓝框
                half4 atlas = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv);
                half3 bg = lerp(half3(0.12, 0.16, 0.2), atlas.rgb, atlas.a);
                float2 cell = i.uv * _Grid.xy;
                float2 f = frac(cell);
                float line_ = step(min(min(f.x, 1 - f.x), min(f.y, 1 - f.y)), 0.015);
                float idx = (_Grid.y - 1 - floor(cell.y)) * _Grid.x + floor(cell.x);
                float total = _Grid.x * _Grid.y;
                float cur = fmod(floor(frame), total), nxt = fmod(floor(frame) + 1, total);
                float border = step(min(min(f.x, 1 - f.x), min(f.y, 1 - f.y)), 0.05);
                bg = lerp(bg, half3(0.5, 0.55, 0.6), line_);
                bg = lerp(bg, half3(1.0, 0.45, 0.15), border * (idx == cur));
                bg = lerp(bg, half3(0.25, 0.6, 1.0), border * (idx == nxt));
                return half4(bg, 1);
            #endif

                float2 uvA = FlipbookUV(i.uv, frame, _Grid.xy);
                half4 c = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uvA);
            #if defined(_FLIPBOOK_BLEND)
                // 帧间混合：再采一张“下一帧”，按小数部分线性插值。代价是多一次采样
                float2 uvB = FlipbookUV(i.uv, frame + 1.0, _Grid.xy);
                half4 cB = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uvB);
                c = lerp(c, cB, frac(frame));
            #endif
                c *= _BaseColor * i.color;
                return c;
            }
            //#endregion
            ENDHLSL
        }
    }
}
