// 配套贴图的导入规则：*_normal 设为法线贴图；数据类贴图关闭 sRGB；Ramp 用 Clamp。
using UnityEditor;
using UnityEngine;

namespace Cookbook.Core
{
    class CookbookTextureImporter : AssetPostprocessor
    {
        void OnPreprocessTexture()
        {
            if (!assetPath.StartsWith("Assets/Cookbook")) return;
            var ti = (TextureImporter)assetImporter;
            string f = System.IO.Path.GetFileNameWithoutExtension(assetPath).ToLowerInvariant();
            if (f.EndsWith("_normal")) ti.textureType = TextureImporterType.NormalMap;
            if (f.EndsWith("_mask") || f.EndsWith("_height") || f.StartsWith("noise_") || f.StartsWith("flow") || f.EndsWith("_linear"))
                ti.sRGBTexture = false;
            if (f.StartsWith("ramp_")) { ti.wrapMode = TextureWrapMode.Clamp; ti.mipmapEnabled = false; }
            if (f.StartsWith("particle_") || f.StartsWith("flipbook_")) ti.alphaIsTransparency = true;
            ti.anisoLevel = 4;
        }
    }
}
