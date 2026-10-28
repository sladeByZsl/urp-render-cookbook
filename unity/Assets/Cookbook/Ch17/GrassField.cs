// 生成一片草（合并成一个网格）：每根草 7 个顶点、5 个三角形，从根到尖逐渐变窄。
// 顶点数据约定：color.r = 高度权重（根 0，尖 1），color.g = 每根草的随机数，
//              uv1.xyz = 这根草根部的物体空间位置，uv1.w = 草高。
// 把“根部位置”写进每个顶点，Shader 才能让整根草按同一个风场值弯曲。
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

namespace Cookbook.Ch17
{
    public static class GrassField
    {
        //#region build
        public static Mesh Build(float size, int count, int seed = 7)
        {
            var rnd = new System.Random(seed);
            float R() => (float)rnd.NextDouble();
            var v = new List<Vector3>(); var n = new List<Vector3>(); var c = new List<Color>();
            var uv = new List<Vector2>(); var uv1 = new List<Vector4>(); var idx = new List<int>();
            float[] hs = { 0f, 0.35f, 0.7f };                     // 三段的高度比例
            for (int b = 0; b < count; b++)
            {
                var root = new Vector3((R() - 0.5f) * size, 0, (R() - 0.5f) * size);
                float height = 0.35f + 0.35f * R();
                float width = 0.03f + 0.02f * R();
                float yaw = R() * Mathf.PI * 2f;
                var side = new Vector3(Mathf.Cos(yaw), 0, Mathf.Sin(yaw));      // 叶片宽度方向
                var face = Vector3.Cross(side, Vector3.up);                      // 叶片朝向
                float lean = (R() - 0.5f) * 0.25f;                               // 自然的前倾
                float random = R();
                int start = v.Count;
                for (int k = 0; k < 3; k++)
                {
                    float h = hs[k], w = width * (1f - h * 0.8f);
                    var center = root + Vector3.up * (h * height) + face * (lean * h * h * height);
                    v.Add(center - side * w); v.Add(center + side * w);
                    for (int s = 0; s < 2; s++)
                    {
                        n.Add(face); c.Add(new Color(h, random, 0, 1));
                        uv.Add(new Vector2(s, h)); uv1.Add(new Vector4(root.x, root.y, root.z, height));
                    }
                }
                v.Add(root + Vector3.up * height + face * (lean * height));      // 草尖
                n.Add(face); c.Add(new Color(1, random, 0, 1)); uv.Add(new Vector2(0.5f, 1)); uv1.Add(new Vector4(root.x, root.y, root.z, height));
                for (int k = 0; k < 2; k++)
                {
                    int a = start + k * 2;
                    idx.AddRange(new[] { a, a + 2, a + 1, a + 1, a + 2, a + 3 });
                }
                idx.AddRange(new[] { start + 4, start + 6, start + 5 });
            }
            var m = new Mesh { name = "GrassField", indexFormat = IndexFormat.UInt32 };
            m.SetVertices(v); m.SetNormals(n); m.SetColors(c); m.SetUVs(0, uv); m.SetUVs(1, uv1);
            m.SetTriangles(idx, 0);
            // 顶点会被风吹离原位：包围盒要留余量，否则摄像机边缘的草会被错误剔除
            m.bounds = new Bounds(new Vector3(0, 0.4f, 0), new Vector3(size + 1.5f, 2f, size + 1.5f));
            return m;
        }
        //#endregion
    }
}
