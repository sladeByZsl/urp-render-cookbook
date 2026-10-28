// 第 22 章配图用的程序化贴花贴图：警示条纹、弹孔（含法线）、脚印、血迹、箭头。全部带 Alpha。
using UnityEngine;

namespace Cookbook.Ch22
{
    public static class DecalTextures
    {
        const int Size = 256;
        static Texture2D s_Hazard, s_HazardClean, s_Hole, s_HoleNormal, s_Foot, s_Blood, s_Arrow, s_Concrete;

        static float Hash(int x, int y, int seed)
        {
            unchecked
            {
                uint h = (uint)(x * 374761393 + y * 668265263 + seed * 1442695041);
                h = (h ^ (h >> 13)) * 1274126177u; h ^= h >> 16;
                return (h & 0xffffff) / 16777215f;
            }
        }
        static float Value(float x, float y, int seed)
        {
            int x0 = Mathf.FloorToInt(x), y0 = Mathf.FloorToInt(y);
            float fx = x - x0, fy = y - y0;
            fx = fx * fx * (3 - 2 * fx); fy = fy * fy * (3 - 2 * fy);
            return Mathf.Lerp(Mathf.Lerp(Hash(x0, y0, seed), Hash(x0 + 1, y0, seed), fx),
                              Mathf.Lerp(Hash(x0, y0 + 1, seed), Hash(x0 + 1, y0 + 1, seed), fx), fy);
        }
        static float Fbm(float x, float y, int seed, int oct = 4)
        {
            float s = 0, a = 0.5f, n = 0;
            for (int i = 0; i < oct; i++) { s += Value(x, y, seed + i * 17) * a; n += a; a *= 0.5f; x *= 2.03f; y *= 2.03f; }
            return s / n;
        }
        static float Smooth(float a, float b, float x) { float t = Mathf.Clamp01((x - a) / (b - a)); return t * t * (3 - 2 * t); }

        static Texture2D Make(string name, bool linear, System.Func<float, float, Color> f)
        {
            var t = new Texture2D(Size, Size, TextureFormat.RGBA32, true, linear)
            { name = name, wrapMode = TextureWrapMode.Clamp, filterMode = FilterMode.Trilinear, anisoLevel = 4, hideFlags = HideFlags.DontSave };
            var px = new Color[Size * Size];
            for (int y = 0; y < Size; y++)
                for (int x = 0; x < Size; x++)
                    px[y * Size + x] = f((x + 0.5f) / Size, (y + 0.5f) / Size);
            t.SetPixels(px); t.Apply(true, false);
            return t;
        }

        /// 可平铺的值噪声（period 为整数，坐标按周期取模）
        static float TileValue(float x, float y, int period, int seed)
        {
            int x0 = Mathf.FloorToInt(x), y0 = Mathf.FloorToInt(y);
            float fx = x - x0, fy = y - y0;
            fx = fx * fx * (3 - 2 * fx); fy = fy * fy * (3 - 2 * fy);
            int W(int a) { a %= period; return a < 0 ? a + period : a; }
            return Mathf.Lerp(Mathf.Lerp(Hash(W(x0), W(y0), seed), Hash(W(x0 + 1), W(y0), seed), fx),
                              Mathf.Lerp(Hash(W(x0), W(y0 + 1), seed), Hash(W(x0 + 1), W(y0 + 1), seed), fx), fy);
        }

        /// 水泥地：低对比度的可平铺噪声 + 少量污渍
        public static Texture2D Concrete
        {
            get
            {
                if (s_Concrete) return s_Concrete;
                var t = Make("ch22_concrete", false, (u, v) =>
                {
                    float n = 0, a = 0.5f, norm = 0; int p = 4;
                    for (int i = 0; i < 5; i++) { n += TileValue(u * p, v * p, p, 51 + i) * a; norm += a; a *= 0.5f; p *= 2; }
                    n /= norm;
                    float grain = TileValue(u * 128, v * 128, 128, 60);
                    float g = 0.52f + (n - 0.5f) * 0.22f + (grain - 0.5f) * 0.08f;
                    return new Color(g * 1.02f, g, g * 0.96f, 1);
                });
                t.wrapMode = TextureWrapMode.Repeat;
                return s_Concrete = t;
            }
        }

        /// 不带磨损的警示条纹（看 Z-Fighting 用，免得把磨损的洞误认为闪烁）
        public static Texture2D HazardClean => s_HazardClean ? s_HazardClean : (s_HazardClean = Make("ch22_hazard_clean", false, (u, v) =>
        {
            float stripe = Mathf.Repeat((u + v) * 5f, 1f) < 0.5f ? 1 : 0;
            var c = stripe > 0.5f ? new Color(0.95f, 0.72f, 0.05f) : new Color(0.06f, 0.06f, 0.06f);
            c.a = 1;
            return c;
        }));

        /// 黄黑警示条纹方块，边缘有磨损
        public static Texture2D Hazard => s_Hazard ? s_Hazard : (s_Hazard = Make("ch22_hazard", false, (u, v) =>
        {
            float edge = Mathf.Min(Mathf.Min(u, 1 - u), Mathf.Min(v, 1 - v));
            float stripe = Mathf.Repeat((u + v) * 5f, 1f) < 0.5f ? 1 : 0;
            bool border = edge < 0.06f;
            var c = border ? new Color(0.08f, 0.08f, 0.08f) : (stripe > 0.5f ? new Color(0.95f, 0.72f, 0.05f) : new Color(0.06f, 0.06f, 0.06f));
            float wear = Fbm(u * 9, v * 9, 3);
            float a = Smooth(0.0f, 0.02f, edge) * Smooth(0.28f, 0.42f, wear);
            c.a = a;
            return c;
        }));

        static float HoleHeight(float u, float v)
        {
            float dx = u - 0.5f, dy = v - 0.5f;
            float r = Mathf.Sqrt(dx * dx + dy * dy) * 2f;
            float hole = -Smooth(0.22f, 0.08f, r);                          // 中心的洞
            float rim = Mathf.Exp(-Mathf.Pow((r - 0.26f) * 10f, 2)) * 0.35f;  // 翻起的边
            float ang = Mathf.Atan2(dy, dx);
            float cracks = Smooth(0.75f, 1f, Value(ang * 4f + 10f, 0.5f, 5)) * Smooth(0.9f, 0.3f, r) * -0.15f;
            return hole + rim + cracks;
        }

        /// 弹孔：中心黑洞 + 灼烧环 + 放射裂纹
        public static Texture2D BulletHole => s_Hole ? s_Hole : (s_Hole = Make("ch22_hole", false, (u, v) =>
        {
            float dx = u - 0.5f, dy = v - 0.5f;
            float r = Mathf.Sqrt(dx * dx + dy * dy) * 2f;
            float ang = Mathf.Atan2(dy, dx);
            float crack = Smooth(0.75f, 1f, Value(ang * 4f + 10f, 0.5f, 5)) * Smooth(0.95f, 0.3f, r);
            float soot = Smooth(0.85f, 0.2f, r + (Fbm(u * 6, v * 6, 7) - 0.5f) * 0.4f);
            var c = Color.Lerp(new Color(0.35f, 0.33f, 0.3f), new Color(0.05f, 0.045f, 0.04f), Mathf.Max(soot, crack * 0.8f));
            if (r < 0.18f) c = new Color(0.01f, 0.01f, 0.01f);
            c.a = Mathf.Clamp01(Mathf.Max(soot, crack)) * Smooth(1f, 0.85f, r);
            return c;
        }));

        /// 弹孔法线（按 DXT5nm 布局写入 (1, y, y, x)，与 UnpackNormal 在桌面平台的解码一致）
        public static Texture2D BulletHoleNormal
        {
            get
            {
                if (s_HoleNormal) return s_HoleNormal;
                const float e = 1f / Size, k = 0.04f;
                return s_HoleNormal = Make("ch22_hole_normal", true, (u, v) =>
                {
                    float hx = (HoleHeight(u + e, v) - HoleHeight(u - e, v)) / (2 * e) * k;
                    float hy = (HoleHeight(u, v + e) - HoleHeight(u, v - e)) / (2 * e) * k;
                    var n = new Vector3(-hx, -hy, 1).normalized;
                    return new Color(1, n.y * 0.5f + 0.5f, n.y * 0.5f + 0.5f, n.x * 0.5f + 0.5f);
                });
            }
        }

        /// 鞋印：前掌 + 后跟两个椭圆，带横向鞋纹
        public static Texture2D Footprint => s_Foot ? s_Foot : (s_Foot = Make("ch22_foot", false, (u, v) =>
        {
            float x = (u - 0.5f) * 2f, y = (v - 0.5f) * 2f;
            float fore = (x * x) / (0.42f * 0.42f) + ((y - 0.32f) * (y - 0.32f)) / (0.55f * 0.55f);
            float heel = (x * x) / (0.32f * 0.32f) + ((y + 0.6f) * (y + 0.6f)) / (0.3f * 0.3f);
            float inside = Mathf.Max(Smooth(1.05f, 0.9f, fore), Smooth(1.05f, 0.9f, heel));
            float tread = Mathf.Repeat(y * 9f, 1f) < 0.55f ? 1f : 0.45f;
            float dirt = Fbm(u * 8, v * 8, 11);
            var c = new Color(0.16f, 0.12f, 0.08f);
            c.a = inside * tread * Smooth(0.15f, 0.45f, dirt);
            return c;
        }));

        /// 血迹：中心一摊 + 四周飞溅的小点
        public static Texture2D Blood => s_Blood ? s_Blood : (s_Blood = Make("ch22_blood", false, (u, v) =>
        {
            float x = u - 0.5f, y = v - 0.5f;
            float r = Mathf.Sqrt(x * x + y * y) * 2f;
            float blob = Smooth(0.5f, 0.38f, r + (Fbm(u * 5, v * 5, 21) - 0.5f) * 0.45f);
            float drops = 0;
            for (int i = 0; i < 24; i++)
            {
                float a = Hash(i, 0, 31) * Mathf.PI * 2, d = 0.45f + Hash(i, 1, 31) * 0.45f, s = 0.012f + Hash(i, 2, 31) * 0.035f;
                float px = 0.5f + Mathf.Cos(a) * d * 0.5f, py = 0.5f + Mathf.Sin(a) * d * 0.5f;
                float dd = Mathf.Sqrt((u - px) * (u - px) + (v - py) * (v - py));
                drops = Mathf.Max(drops, Smooth(s, s * 0.6f, dd));
            }
            float a2 = Mathf.Max(blob, drops);
            var c = Color.Lerp(new Color(0.35f, 0.02f, 0.02f), new Color(0.18f, 0.0f, 0.01f), Fbm(u * 10, v * 10, 22));
            c.a = a2 * 0.92f;
            return c;
        }));

        /// 地面喷漆箭头
        public static Texture2D Arrow => s_Arrow ? s_Arrow : (s_Arrow = Make("ch22_arrow", false, (u, v) =>
        {
            float x = u - 0.5f, y = v;
            bool shaft = Mathf.Abs(x) < 0.11f && y > 0.08f && y < 0.6f;
            bool head = y >= 0.55f && y < 0.92f && Mathf.Abs(x) < (0.92f - y) * 0.85f;
            float spray = Fbm(u * 14, v * 14, 41);
            var c = new Color(0.95f, 0.95f, 0.92f);
            c.a = (shaft || head) ? Smooth(0.2f, 0.4f, spray) * 0.95f : 0;
            return c;
        }));
    }
}
