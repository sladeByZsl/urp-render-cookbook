// 配套工程一键设置：线性色彩空间 + 一份 URP Asset（Forward+ / Depth / Opaque Texture 打开）
using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Cookbook.Core
{
    public static class BookSetup
    {
        const string Dir = "Assets/Settings";

        [MenuItem("Cookbook/Setup Project (URP Asset + Linear)")]
        public static void Setup()
        {
            PlayerSettings.colorSpace = ColorSpace.Linear;
            if (!AssetDatabase.IsValidFolder(Dir)) AssetDatabase.CreateFolder("Assets", "Settings");

            var asset = AssetDatabase.LoadAssetAtPath<UniversalRenderPipelineAsset>(Dir + "/URP-Cookbook.asset");
            if (asset == null)
            {
                var data = ScriptableObject.CreateInstance<UniversalRendererData>();
                AssetDatabase.CreateAsset(data, Dir + "/URP-Cookbook_Renderer.asset");
                ResourceReloader.ReloadAllNullIn(data, UniversalRenderPipelineAsset.packagePath);
                data.postProcessData = AssetDatabase.LoadAssetAtPath<PostProcessData>(
                    UniversalRenderPipelineAsset.packagePath + "/Runtime/Data/PostProcessData.asset");
                data.renderingMode = RenderingMode.ForwardPlus;

                asset = UniversalRenderPipelineAsset.Create(data);
                asset.supportsCameraDepthTexture = true;
                asset.supportsCameraOpaqueTexture = true;
                asset.supportsHDR = true;
                asset.msaaSampleCount = 4;
                asset.shadowDistance = 50f;
                asset.shadowCascadeCount = 4;
                AssetDatabase.CreateAsset(asset, Dir + "/URP-Cookbook.asset");
                var so = new SerializedObject(asset);
                so.FindProperty("m_SoftShadowsSupported").boolValue = true;
                so.ApplyModifiedPropertiesWithoutUndo();
            }

            GraphicsSettings.defaultRenderPipeline = asset;
            for (int i = 0; i < QualitySettings.names.Length; i++)
            {
                QualitySettings.SetQualityLevel(i, false);
                QualitySettings.renderPipeline = asset;
            }
            AssetDatabase.SaveAssets();
            Debug.Log("[Cookbook] Project setup done: " + AssetDatabase.GetAssetPath(asset));
        }
    }
}
