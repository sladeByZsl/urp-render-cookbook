// 教学用的“迷你烘焙器”：给一块地面算一张只含天空光遮蔽的光照贴图。
// 它做的事情和 Progressive Lightmapper 的核心一样——对每个纹素，在半球上发射光线、
// 看哪些方向能看到天空、按余弦加权求平均——只是场景被简化成“地面 + 若干球”，并且只算一次弹射。
using System;
using UnityEngine;

namespace Cookbook.Ch08
{
    public static class ManualLightmapBaker
    {
        //#region bake
        /// size：地面边长（米），地面是中心在原点、朝 +Y 的正方形，uv(0,0) 对应 (-size/2, 0, -size/2)
        /// spheres：遮挡球（xyz = 球心，w = 半径）
        /// 返回值：每个纹素存的是 URP 约定下的间接漫反射 bakedGI（= 辐照度 / π），线性空间
        public static Texture2D BakeFloor(int resolution, float size, Vector4[] spheres, Func<Vector3, Color> sky, int samples = 256)
        {
            var tex = new Texture2D(resolution, resolution, TextureFormat.RGBAHalf, false, true)
            {
                name = "ManualLightmap", wrapMode = TextureWrapMode.Clamp, filterMode = FilterMode.Bilinear, hideFlags = HideFlags.DontSave
            };
            var px = new Color[resolution * resolution];
            int sq = Mathf.Max(1, Mathf.RoundToInt(Mathf.Sqrt(samples)));
            for (int y = 0; y < resolution; y++)
                for (int x = 0; x < resolution; x++)
                {
                    var p = new Vector3(((x + 0.5f) / resolution - 0.5f) * size, 0.001f, ((y + 0.5f) / resolution - 0.5f) * size);
                    Color sum = Color.black;
                    for (int i = 0; i < sq; i++)
                        for (int j = 0; j < sq; j++)
                        {
                            // 余弦加权的半球方向（法线 = +Y），pdf 与 cosθ/π 抵消 → 结果是可见天空的简单平均
                            float u1 = (i + 0.5f) / sq, u2 = (j + 0.5f) / sq;
                            float r = Mathf.Sqrt(u1), phi = 2f * Mathf.PI * u2;
                            var d = new Vector3(r * Mathf.Cos(phi), Mathf.Sqrt(1f - u1), r * Mathf.Sin(phi));
                            if (!Occluded(p, d, spheres)) sum += sky(d);
                        }
                    px[y * resolution + x] = sum / (sq * sq);
                }
            tex.SetPixels(px);
            tex.Apply(false, false);
            return tex;
        }

        // 光线与球求交：只要有一个球挡住就算被遮挡（不考虑球表面的二次反弹）
        static bool Occluded(Vector3 o, Vector3 d, Vector4[] spheres)
        {
            foreach (var s in spheres)
            {
                Vector3 oc = o - (Vector3)s;
                float b = Vector3.Dot(oc, d);
                float c = Vector3.Dot(oc, oc) - s.w * s.w;
                float h = b * b - c;
                if (h >= 0 && -b - Mathf.Sqrt(h) > 0) return true;
            }
            return false;
        }
        //#endregion
    }
}
