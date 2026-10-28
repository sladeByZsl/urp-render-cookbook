// 程序化地形网格：给一个高度函数 h(x, z)，生成带法线、切线、UV 的规则网格。
// 本章的地形配图都用它，不依赖 Unity Terrain 组件，方便看清 Shader 本身做了什么。
using System;
using UnityEngine;
using UnityEngine.Rendering;

namespace Cookbook.Ch20
{
    public static class Heightfield
    {
        //#region build
        /// <param name="size">边长（米），网格中心在原点</param>
        /// <param name="n">每边段数，顶点数 (n+1)²</param>
        /// <param name="height">高度函数，输入世界 x/z，输出 y</param>
        public static Mesh Build(float size, int n, Func<float, float, float> height)
        {
            int vc = (n + 1) * (n + 1);
            var v = new Vector3[vc];
            var nr = new Vector3[vc];
            var uv = new Vector2[vc];
            float step = size / n;
            for (int z = 0; z <= n; z++)
                for (int x = 0; x <= n; x++)
                {
                    float wx = -size * 0.5f + x * step, wz = -size * 0.5f + z * step;
                    int k = z * (n + 1) + x;
                    v[k] = new Vector3(wx, height(wx, wz), wz);
                    uv[k] = new Vector2((float)x / n, (float)z / n);
                    // 中心差分求法线：N = normalize(-dh/dx, 1, -dh/dz)
                    float e = step * 0.5f;
                    float dx = (height(wx + e, wz) - height(wx - e, wz)) / (2 * e);
                    float dz = (height(wx, wz + e) - height(wx, wz - e)) / (2 * e);
                    nr[k] = new Vector3(-dx, 1f, -dz).normalized;
                }
            var idx = new int[n * n * 6];
            int p = 0;
            for (int z = 0; z < n; z++)
                for (int x = 0; x < n; x++)
                {
                    int a = z * (n + 1) + x, b = a + n + 1;
                    idx[p++] = a; idx[p++] = b; idx[p++] = a + 1;
                    idx[p++] = a + 1; idx[p++] = b; idx[p++] = b + 1;
                }
            var m = new Mesh { name = "Heightfield", indexFormat = IndexFormat.UInt32 };
            m.vertices = v; m.normals = nr; m.uv = uv; m.triangles = idx;
            m.RecalculateTangents();
            m.RecalculateBounds();
            return m;
        }
        //#endregion

        /// 多倍频 Perlin 噪声（fBm），返回大约 0..1
        public static float Fbm(float x, float z, int octaves = 5)
        {
            float sum = 0, amp = 0.5f, freq = 1, norm = 0;
            for (int i = 0; i < octaves; i++)
            {
                sum += Mathf.PerlinNoise(x * freq + i * 17.13f, z * freq - i * 9.71f) * amp;
                norm += amp; amp *= 0.5f; freq *= 2.03f;
            }
            return sum / norm;
        }

        static float Smooth(float a, float b, float x) { float t = Mathf.Clamp01((x - a) / (b - a)); return t * t * (3 - 2 * t); }

        /// 本章配图用的“示范地形”：前景平缓草地、中景带陡崖的台地、背景一座雪山
        public static float DemoHeight(float x, float z)
        {
            float hills = (Fbm(x * 0.045f + 3.1f, z * 0.045f + 7.7f) - 0.45f) * 3.2f;
            // 台地：用噪声阈值做出陡峭的崖壁
            float mesaMask = Smooth(0.50f, 0.56f, Fbm(x * 0.05f + 21f, z * 0.05f + 4f, 3) + Smooth(-2f, 14f, z) * 0.12f);
            float mesa = mesaMask * (2.6f + Fbm(x * 0.2f, z * 0.2f, 3) * 0.6f);
            // 雪山：高斯包络 × 脊状噪声
            float dx = x - 6f, dz = z - 26f;
            float env = Mathf.Exp(-(dx * dx + dz * dz) / (2f * 9f * 9f));
            float ridge = 1f - Mathf.Abs(Fbm(x * 0.08f + 40f, z * 0.08f + 3f, 4) * 2f - 1f);
            float mountain = env * (9f + ridge * 4f);
            return hills + mesa + mountain;
        }

        /// 一块“石头”：UV 球按噪声沿法线起伏，用来看 Triplanar 法线
        public static Mesh Rock(float radius = 1f, int seg = 96, float bump = 0.18f, float seed = 0f)
        {
            int rings = seg / 2;
            int vc = (seg + 1) * (rings + 1);
            var v = new Vector3[vc];
            var uv = new Vector2[vc];
            for (int r = 0; r <= rings; r++)
                for (int s = 0; s <= seg; s++)
                {
                    float th = Mathf.PI * r / rings, ph = 2 * Mathf.PI * s / seg;
                    var d = new Vector3(Mathf.Sin(th) * Mathf.Cos(ph), Mathf.Cos(th), Mathf.Sin(th) * Mathf.Sin(ph));
                    // 用三个平面上的 Perlin 噪声平均，近似 3D 噪声
                    float nz = (Fbm(d.x * 1.3f + seed, d.y * 1.3f, 4) + Fbm(d.y * 1.3f, d.z * 1.3f + seed, 4) + Fbm(d.z * 1.3f + 5, d.x * 1.3f, 4)) / 3f;
                    float rr = radius * (1f + (nz - 0.5f) * 2f * bump);
                    int k = r * (seg + 1) + s;
                    v[k] = new Vector3(d.x * rr, d.y * rr * 0.8f, d.z * rr);
                    uv[k] = new Vector2((float)s / seg, (float)r / rings);
                }
            var idx = new int[seg * rings * 6];
            int p = 0;
            for (int r = 0; r < rings; r++)
                for (int s = 0; s < seg; s++)
                {
                    int a = r * (seg + 1) + s, b = a + seg + 1;
                    idx[p++] = a; idx[p++] = a + 1; idx[p++] = b;
                    idx[p++] = b; idx[p++] = a + 1; idx[p++] = b + 1;
                }
            var m = new Mesh { name = "Rock", indexFormat = IndexFormat.UInt32 };
            m.vertices = v; m.uv = uv; m.triangles = idx;
            m.RecalculateNormals();
            // UV 球接缝处顶点重复，RecalculateNormals 会留下一条硬缝；把接缝两侧的法线取平均
            var nr = m.normals;
            for (int r = 0; r <= rings; r++)
            {
                int a = r * (seg + 1), b = a + seg;
                var avg = (nr[a] + nr[b]).normalized; nr[a] = avg; nr[b] = avg;
            }
            m.normals = nr;
            m.RecalculateTangents();
            m.RecalculateBounds();
            return m;
        }
    }
}
