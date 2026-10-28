// 程序化生成 Matcap：对圆盘内每个像素反推出球面法线 n = (x, y, sqrt(1 - x² - y²))，
// 用任意“着色函数”算出颜色。这样一张图就“冻结”了一种光照 + 材质的组合。
using System;
using UnityEngine;

namespace Cookbook.Ch15
{
    public static class MatcapGenerator
    {
        //#region gen
        public static Texture2D Build(int size, Func<Vector3, Color> shade, string name = "MatCap")
        {
            var tex = new Texture2D(size, size, TextureFormat.RGBA32, true, false)
            { name = name, wrapMode = TextureWrapMode.Clamp, filterMode = FilterMode.Trilinear };
            var px = new Color[size * size];
            for (int y = 0; y < size; y++)
                for (int x = 0; x < size; x++)
                {
                    float u = (x + 0.5f) / size * 2f - 1f, v = (y + 0.5f) / size * 2f - 1f;
                    float r2 = u * u + v * v;
                    // 圆盘外的像素也给一个合理值（取边缘法线），防止双线性/mip 把黑边混进来
                    float k = r2 > 1f ? 1f / Mathf.Sqrt(r2) : 1f;
                    var n = new Vector3(u * k, v * k, Mathf.Sqrt(Mathf.Max(0f, 1f - r2 * k * k)));
                    px[y * size + x] = shade(n);
                }
            tex.SetPixels(px); tex.Apply(true);
            return tex;
        }
        //#endregion

        static float Sat(float x) => Mathf.Clamp01(x);

        /// 陶土：大面积柔和漫反射 + 冷色反光 + 一点暖色边缘
        public static Color Clay(Vector3 n)
        {
            var L = new Vector3(-0.5f, 0.6f, 0.62f).normalized;
            float d = Sat(Vector3.Dot(n, L) * 0.6f + 0.4f);
            float rim = Mathf.Pow(1f - n.z, 3f);
            var c = Color.Lerp(new Color(0.28f, 0.12f, 0.1f), new Color(0.85f, 0.45f, 0.35f), d);
            c += new Color(0.25f, 0.28f, 0.4f) * rim * Sat(-n.y + 0.3f);       // 底部冷反光
            float spec = Mathf.Pow(Sat(Vector3.Dot(n, (L + Vector3.forward).normalized)), 30f) * 0.25f;
            return c + new Color(spec, spec, spec);
        }

        /// 卡通：三阶色 + 硬高光 + 亮边
        public static Color Toon(Vector3 n)
        {
            var L = new Vector3(-0.45f, 0.55f, 0.7f).normalized;
            float d = Vector3.Dot(n, L);
            Color baseC = new Color(0.25f, 0.55f, 0.85f);
            Color c = d > 0.55f ? baseC : d > 0.05f ? baseC * 0.72f : baseC * 0.45f;
            c.a = 1;
            float h = Vector3.Dot(n, (L + Vector3.forward).normalized);
            if (h > 0.985f) c = new Color(0.95f, 0.98f, 1f);
            if (n.z < 0.28f && n.y > -0.2f) c = Color.Lerp(c, new Color(0.7f, 0.9f, 1f), 0.6f);
            return c;
        }

        /// 金属漆：天空/地平线/地面的环境条纹 + 尖锐高光（典型的“车漆”Matcap）
        public static Color Chrome(Vector3 n)
        {
            var r = new Vector3(2 * n.z * n.x, 2 * n.z * n.y, 2 * n.z * n.z - 1);   // 视线 (0,0,-1) 的反射方向
            float y = r.y;
            Color sky = Color.Lerp(new Color(0.9f, 0.85f, 0.7f), new Color(0.25f, 0.4f, 0.75f), Sat(y * 1.6f));
            Color ground = Color.Lerp(new Color(0.35f, 0.25f, 0.2f), new Color(0.08f, 0.06f, 0.06f), Sat(-y * 2.5f));
            Color c = y > 0 ? sky : ground;
            c *= new Color(1f, 0.82f, 0.55f);                                       // 金色金属：反射被本色染色
            float spec = Mathf.Pow(Sat(Vector3.Dot(n, new Vector3(-0.35f, 0.45f, 0.82f).normalized)), 200f) * 2f;
            c += new Color(spec, spec, spec);
            c.a = 1;
            return c;
        }
    }
}
