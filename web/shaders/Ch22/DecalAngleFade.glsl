// 案例 22.3：开启了 Angle Fade 的贴花 Shader Graph（Ch22/DecalAngleFade.shadergraph）的手写 GLSL 版。
// 节点图与 URP 自带的 Decal Graph 完全相同：
//   Base Map ─ Sample Texture 2D ─┬─ RGB → Base Color
//                                 └─ A ──┬→ Alpha
//                                        └→ Multiply（× Normal Blend）→ Normal Alpha
//   Normal Map ─ Sample Texture 2D（Type = Normal）→ Normal (Tangent Space)
// 唯一的区别在 Graph Settings：Angle Fade 打开（生成代码里多了 DECAL_ANGLE_FADE），
// Decal Projector 上的 Start/End Angle Fade 才会生效。
Shader "Cookbook/Ch22/DecalAngleFade"
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
            vec4 baseMap = texture(Base_Map, uv);
            normalTS = UnpackNormal(texture(Normal_Map, uv));
            baseColor = baseMap.rgb;
            alpha = baseMap.a;
            normalAlpha = baseMap.a * Normal_Blend;
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
            #define DECAL_ANGLE_FADE
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
            #define DECAL_ANGLE_FADE
            #include "URP/ShaderPassDecal.glsl"
            ENDGLSL
        }
    }
}
