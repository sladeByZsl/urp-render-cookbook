// 菜单：把程序生成的 DFG LUT 存成资产，拖给 MyPBR 材质的 DFG LUT 槽并勾选 Use DFG LUT。
using UnityEditor;
using UnityEngine;

namespace Cookbook.Ch11
{
    static class DFGLutBaker
    {
        const string Path = "Assets/Cookbook/Ch11/MyPBR_DFG_LUT.asset";

        [MenuItem("Cookbook/Ch11/Bake DFG LUT")]
        static void Bake()
        {
            var tex = DFGLut.Generate(64, 1024);
            AssetDatabase.CreateAsset(tex, Path);
            AssetDatabase.SaveAssets();
            EditorGUIUtility.PingObject(tex);
            Debug.Log("[Ch11] DFG LUT baked: " + Path);
        }
    }
}
