// 程序化网格：圆环、环面纽结、细分平面。带法线、切线和 UV，可直接给法线贴图类 Shader 用。
using UnityEngine;
using UnityEngine.Rendering;

namespace Cookbook.Core
{
    public static class Meshes
    {
        static Mesh Tube(System.Func<float, Vector3> curve, float radius, int seg, int side, float uvRepeatU)
        {
            int vc = (seg + 1) * (side + 1);
            var v = new Vector3[vc]; var n = new Vector3[vc]; var uv = new Vector2[vc];
            for (int i = 0; i <= seg; i++)
            {
                float t = (float)i / seg;
                Vector3 c = curve(t);
                Vector3 T = (curve(t + 0.0005f) - curve(t - 0.0005f)).normalized;
                Vector3 B = Vector3.Cross(T, c).normalized;
                if (B.sqrMagnitude < 1e-6f) B = Vector3.Cross(T, Vector3.up).normalized;
                Vector3 N = Vector3.Cross(B, T);
                for (int j = 0; j <= side; j++)
                {
                    float a = (float)j / side * Mathf.PI * 2f;
                    Vector3 dir = Mathf.Cos(a) * N + Mathf.Sin(a) * B;
                    int k = i * (side + 1) + j;
                    v[k] = c + dir * radius; n[k] = dir; uv[k] = new Vector2(t * uvRepeatU, (float)j / side);
                }
            }
            var idx = new int[seg * side * 6]; int p = 0;
            for (int i = 0; i < seg; i++)
                for (int j = 0; j < side; j++)
                {
                    int a = i * (side + 1) + j, b = a + side + 1;
                    idx[p++] = a; idx[p++] = a + 1; idx[p++] = b;
                    idx[p++] = b; idx[p++] = a + 1; idx[p++] = b + 1;
                }
            var m = new Mesh { indexFormat = IndexFormat.UInt32 };
            m.vertices = v; m.normals = n; m.uv = uv; m.triangles = idx;
            m.RecalculateTangents(); m.RecalculateBounds();
            return m;
        }

        public static Mesh Torus(float R = 0.7f, float r = 0.28f) =>
            Tube(t => new Vector3(Mathf.Cos(t * Mathf.PI * 2) * R, 0, Mathf.Sin(t * Mathf.PI * 2) * R), r, 128, 48, 4);

        /// (2,3) 环面纽结，直径约 1.6
        public static Mesh TorusKnot(float scale = 0.32f, float tube = 0.16f) =>
            Tube(t =>
            {
                float u = t * Mathf.PI * 2f, p = 2, q = 3;
                float rr = 2f + Mathf.Cos(q * u);
                return new Vector3(rr * Mathf.Cos(p * u), -Mathf.Sin(q * u), rr * Mathf.Sin(p * u)) * scale;
            }, tube, 512, 48, 8);

        public static Mesh Grid(float size = 4f, int n = 128)
        {
            int vc = (n + 1) * (n + 1);
            var v = new Vector3[vc]; var uv = new Vector2[vc]; var nr = new Vector3[vc];
            for (int z = 0; z <= n; z++)
                for (int x = 0; x <= n; x++)
                {
                    int k = z * (n + 1) + x;
                    v[k] = new Vector3(((float)x / n - 0.5f) * size, 0, ((float)z / n - 0.5f) * size);
                    uv[k] = new Vector2((float)x / n, (float)z / n); nr[k] = Vector3.up;
                }
            var idx = new int[n * n * 6]; int p = 0;
            for (int z = 0; z < n; z++)
                for (int x = 0; x < n; x++)
                {
                    int a = z * (n + 1) + x, b = a + n + 1;
                    idx[p++] = a; idx[p++] = b; idx[p++] = a + 1;
                    idx[p++] = a + 1; idx[p++] = b; idx[p++] = b + 1;
                }
            var m = new Mesh { indexFormat = IndexFormat.UInt32 };
            m.vertices = v; m.uv = uv; m.normals = nr; m.triangles = idx;
            m.RecalculateTangents(); m.bounds = new Bounds(Vector3.zero, new Vector3(size, size, size));
            return m;
        }
    }
}
