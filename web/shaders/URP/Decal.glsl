// URP 自带的贴花 Shader Graph（Packages/.../Shaders/Decal.shadergraph）的手写 GLSL 版。
// 节点图：Base_Map → Base Color / Alpha；Normal_Map（法线类型采样）→ Normal (Tangent Space)；Base_Map.A × Normal_Blend → Normal Alpha。
// 投影、深度重建、光照在 URP/ShaderPassDecal.glsl 里（对应 URP 的 ShaderPassDecal.hlsl），由 DecalRendererFeature 逐个投影器绘制。
Shader "Shader Graphs/Decal"
{
    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "PreviewType"="Plane" }

        GLSLINCLUDE
        uniform sampler2D Base_Map;
        uniform sampler2D Normal_Map;
        uniform float Normal_Blend;

        void DecalGraph(vec2 uv, out vec3 baseColor, out float alpha, out vec3 normalTS, out float normalAlpha)
        {
            vec4 baseMap = texture(Base_Map, uv);                    // Sample Texture 2D（Base Map）
            normalTS = UnpackNormal(texture(Normal_Map, uv));        // Sample Texture 2D（Normal Map，Type = Normal）
            baseColor = baseMap.rgb;
            alpha = baseMap.a;
            normalAlpha = baseMap.a * Normal_Blend;                  // Multiply
        }
        ENDGLSL

        Pass
        {
            Name "DBufferProjector"
            Tags { "LightMode"="DBufferProjector" }
            Cull Front ZTest Greater ZWrite Off
            Blend SrcAlpha OneMinusSrcAlpha
            GLSLPROGRAM
            #define DBUFFER_PROJECTOR
            #include "URP/ShaderPassDecal.glsl"
            ENDGLSL
        }

        Pass
        {
            Name "DecalScreenSpaceProjector"
            Tags { "LightMode"="DecalScreenSpaceProjector" }
            Cull Front ZTest Greater ZWrite Off
            Blend SrcAlpha OneMinusSrcAlpha
            GLSLPROGRAM
            #define SCREEN_SPACE_PROJECTOR
            #include "URP/ShaderPassDecal.glsl"
            ENDGLSL
        }
    }
}
