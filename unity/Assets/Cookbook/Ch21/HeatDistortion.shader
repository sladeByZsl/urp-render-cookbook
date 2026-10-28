// 案例 21.8：热扭曲（Heat Distortion）——采样 _CameraOpaqueTexture，按滚动噪声偏移屏幕 UV
Shader "Cookbook/Ch21/HeatDistortion"
{
    Properties
    {
        [NoScaleOffset] _NoiseTex ("Noise", 2D) = "gray" {}
        [NoScaleOffset] _MaskTex ("Mask (A)", 2D) = "white" {}
        _Strength ("Strength", Range(0, 0.2)) = 0.04
        _NoiseTiling ("Noise Tiling", Vector) = (1.5, 1, 0, 0)
        _RiseSpeed ("Rise Speed", Float) = 0.6
        _Phase ("Phase (for stills)", Float) = 0
        [Toggle] _ShowOffset ("Debug: Show Offset", Float) = 0
    }
    SubShader
    {
        Tags { "RenderType"="Transparent" "RenderPipeline"="UniversalPipeline" "Queue"="Transparent" "IgnoreProjector"="True" }

        Pass
        {
            Name "Distortion"
            Tags { "LightMode"="UniversalForward" }
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            Cull Off
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"

            CBUFFER_START(UnityPerMaterial)
                half _Strength;
                float4 _NoiseTiling;
                float _RiseSpeed, _Phase;
                half _ShowOffset;
            CBUFFER_END
            TEXTURE2D(_NoiseTex); SAMPLER(sampler_NoiseTex);
            TEXTURE2D(_MaskTex);  SAMPLER(sampler_MaskTex);

            struct Attributes { float4 positionOS : POSITION; float2 uv : TEXCOORD0; half4 color : COLOR; UNITY_VERTEX_INPUT_INSTANCE_ID };
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
                float4 screenData : TEXCOORD1;   // xyw = positionNDC，z = 观察空间深度
                half4  color      : COLOR;
            };

            Varyings vert(Attributes v)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                VertexPositionInputs p = GetVertexPositionInputs(v.positionOS.xyz);
                o.positionCS = p.positionCS;
                o.uv = v.uv;
                o.screenData = float4(p.positionNDC.xy, -p.positionVS.z, p.positionNDC.w);
                o.color = v.color;
                return o;
            }

            //#region frag
            half4 frag(Varyings i) : SV_Target
            {
                float t = _Time.y + _Phase;
                // 两次错位采样单通道噪声，拼成一个二维偏移向量；整体向上滚动，像热空气上升
                float2 nuv = i.uv * _NoiseTiling.xy + float2(0, -frac(t * _RiseSpeed));
                half nx = SAMPLE_TEXTURE2D(_NoiseTex, sampler_NoiseTex, nuv).r - 0.5;
                half ny = SAMPLE_TEXTURE2D(_NoiseTex, sampler_NoiseTex, nuv * 1.31 + 0.37).r - 0.5;
                half mask = SAMPLE_TEXTURE2D(_MaskTex, sampler_MaskTex, i.uv).a * i.color.a;

                // 屏幕上的偏移量除以深度：同样的“空气扰动”，离得越远在屏幕上越小
                float2 offset = float2(nx, ny) * (_Strength * mask) / max(i.screenData.z * 0.2, 1.0);

                // 调试：把偏移量放大后显示，R/G = 水平/竖直偏移，0.5 灰为不偏移
                if (_ShowOffset > 0.5) return half4(offset * (1.5 / max(_Strength, 1e-4)) + 0.5, 0.5, 1);

                float2 suv = i.screenData.xy / i.screenData.w;
                half3 scene = SampleSceneColor(suv + offset);
                return half4(scene, saturate(mask * 3.0));
            }
            //#endregion
            ENDHLSL
        }
    }
}
