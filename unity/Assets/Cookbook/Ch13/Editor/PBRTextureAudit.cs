// 菜单：Cookbook/Ch13/Audit PBR Textures —— 按命名约定检查贴图导入设置，并检查材质里法线槽是否放了“非法线贴图”。
// 只报告，不自动修改：导入设置改错了代价很大（会触发重新导入、改变外观），应由人确认。
using System.Collections.Generic;
using System.Linq;
using UnityEditor;
using UnityEngine;

namespace Cookbook.Ch13
{
    public static class PBRTextureAudit
    {
        //#region rules
        // 后缀 -> 期望：颜色类贴图开 sRGB；数据类贴图关 sRGB；法线贴图必须是 Normal Map 类型
        static readonly string[] ColorSuffix = { "_albedo", "_basecolor", "_diffuse", "_color", "_emission" };
        static readonly string[] DataSuffix  = { "_mask", "_metallic", "_roughness", "_smoothness", "_ao", "_occlusion", "_height" };
        static readonly string[] NormalSuffix = { "_normal", "_nrm", "_n" };

        public static List<string> AuditFolder(string folder)
        {
            var issues = new List<string>();
            foreach (var guid in AssetDatabase.FindAssets("t:Texture2D", new[] { folder }))
            {
                string path = AssetDatabase.GUIDToAssetPath(guid);
                if (!(AssetImporter.GetAtPath(path) is TextureImporter ti)) continue;
                string n = System.IO.Path.GetFileNameWithoutExtension(path).ToLowerInvariant();

                if (NormalSuffix.Any(n.EndsWith))
                {
                    if (ti.textureType != TextureImporterType.NormalMap)
                        issues.Add($"{path}: 名字是法线贴图，但 Texture Type 不是 Normal Map（会被当颜色做 sRGB 解码，也不会按法线格式压缩）");
                }
                else if (DataSuffix.Any(n.EndsWith))
                {
                    if (ti.sRGBTexture)
                        issues.Add($"{path}: 数据贴图开启了 sRGB，金属度/光滑度/AO 会被错误地“解码变暗”");
                }
                else if (ColorSuffix.Any(n.EndsWith))
                {
                    if (!ti.sRGBTexture)
                        issues.Add($"{path}: 颜色贴图关闭了 sRGB，颜色会显得发灰、偏亮");
                }
            }
            return issues;
        }

        // 材质的法线槽里放了非 Normal Map 类型的贴图（Inspector 会提示 Fix Now，但批量导入的材质常被忽略）
        public static List<string> AuditMaterials(string folder)
        {
            var issues = new List<string>();
            foreach (var guid in AssetDatabase.FindAssets("t:Material", new[] { folder }))
            {
                var mat = AssetDatabase.LoadAssetAtPath<Material>(AssetDatabase.GUIDToAssetPath(guid));
                foreach (var prop in new[] { "_BumpMap", "_DetailNormalMap" })
                {
                    if (!mat.HasProperty(prop) || !(mat.GetTexture(prop) is Texture2D tex)) continue;
                    if (AssetImporter.GetAtPath(AssetDatabase.GetAssetPath(tex)) is TextureImporter ti && ti.textureType != TextureImporterType.NormalMap)
                        issues.Add($"{mat.name}.{prop} = {tex.name}: 贴图不是 Normal Map 类型");
                }
            }
            return issues;
        }
        //#endregion

        [MenuItem("Cookbook/Ch13/Audit PBR Textures")]
        static void Run()
        {
            string folder = "Assets";
            var sel = Selection.activeObject;
            if (sel != null && AssetDatabase.IsValidFolder(AssetDatabase.GetAssetPath(sel))) folder = AssetDatabase.GetAssetPath(sel);
            var issues = AuditFolder(folder).Concat(AuditMaterials(folder)).ToList();
            foreach (var i in issues) Debug.LogWarning("[PBR Audit] " + i);
            Debug.Log($"[PBR Audit] {folder}: {issues.Count} 个问题");
        }
    }
}
