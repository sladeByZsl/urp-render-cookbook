// 第 20 章配图用的程序化地表贴图：草、岩石（含法线）、雪、砂石。RGB = 颜色，A = 高度（给 Height Blend 用）。
// 全部是可平铺（tileable）的噪声，拍摄时生成，不依赖外部素材。
using UnityEngine;

namespace Cookbook.Ch20
{
    public static class TerrainTextures
    {
        const int Size = 256;
        static Texture2D s_Grass, s_Rock, s_RockNormal, s_Snow, s_Sand;

        // ---------- 可平铺噪声 ----------
        static float Hash(int x, int y, int seed)
        {
            unchecked
            {
                uint h = (uint)(x * 374761393 + y * 668265263 + seed * 1442695041);
                h = (h ^ (h >> 13)) * 1274126177u;
                h ^= h >> 16;
                return (h & 0xffffff) / 16777215f;
            }
        }
        static int Wrap(int a, int p) { a %= p; return a < 0 ? a + p : a; }

        /// 值噪声，u/v 为 0..1，period 为每单位格子数（整数 → 可平铺）
        static float Value(float u, float v, int period, int seed)
        {
            float x = u * period, y = v * period;
            int x0 = Mathf.FloorToInt(x), y0 = Mathf.FloorToInt(y);
            float fx = x - x0, fy = y - y0;
            fx = fx * fx * (3 - 2 * fx); fy = fy * fy * (3 - 2 * fy);
            float a = Hash(Wrap(x0, period), Wrap(y0, period), seed), b = Hash(Wrap(x0 + 1, period), Wrap(y0, period), seed);
            float c = Hash(Wrap(x0, period), Wrap(y0 + 1, period), seed), d = Hash(Wrap(x0 + 1, period), Wrap(y0 + 1, period), seed);
            return Mathf.Lerp(Mathf.Lerp(a, b, fx), Mathf.Lerp(c, d, fx), fy);
        }
        static float Fbm(float u, float v, int basePeriod, int oct, int seed)
        {
            float s = 0, amp = 0.5f, n = 0; int p = basePeriod;
            for (int i = 0; i < oct; i++) { s += Value(u, v, p, seed + i * 31) * amp; n += amp; amp *= 0.5f; p *= 2; }
            return s / n;
        }
        /// Worley：返回最近两个特征点距离 F1、F2，以及最近点所属格子的随机值 id
        static void Worley(float u, float v, int cells, int seed, out float f1, out float f2, out float id)
        {
            float x = u * cells, y = v * cells;
            int cx = Mathf.FloorToInt(x), cy = Mathf.FloorToInt(y);
            f1 = f2 = 9; id = 0;
            for (int j = -1; j <= 1; j++)
                for (int i = -1; i <= 1; i++)
                {
                    int gx = cx + i, gy = cy + j;
                    int wx = Wrap(gx, cells), wy = Wrap(gy, cells);
                    float px = gx + Hash(wx, wy, seed), py = gy + Hash(wx, wy, seed + 7);
                    float d = Mathf.Sqrt((px - x) * (px - x) + (py - y) * (py - y));
                    if (d < f1) { f2 = f1; f1 = d; id = Hash(wx, wy, seed + 13); }
                    else if (d < f2) f2 = d;
                }
        }
        static float Smooth(float a, float b, float x) { float t = Mathf.Clamp01((x - a) / (b - a)); return t * t * (3 - 2 * t); }

        static Texture2D NewTex(string name, bool linear)
        {
            return new Texture2D(Size, Size, TextureFormat.RGBA32, true, linear)
            { name = name, wrapMode = TextureWrapMode.Repeat, filterMode = FilterMode.Trilinear, anisoLevel = 8, hideFlags = HideFlags.DontSave };
        }

        static Texture2D Make(string name, System.Func<float, float, Color> f)
        {
            var t = NewTex(name, false);
            var px = new Color[Size * Size];
            for (int y = 0; y < Size; y++)
                for (int x = 0; x < Size; x++)
                    px[y * Size + x] = f((x + 0.5f) / Size, (y + 0.5f) / Size);
            t.SetPixels(px); t.Apply(true, false);
            return t;
        }

        public static Texture2D Grass => s_Grass ? s_Grass : (s_Grass = Make("ch20_grass", (u, v) =>
        {
            float big = Fbm(u, v, 4, 4, 11);
            float fine = Fbm(u, v, 32, 3, 12);
            // 沿 V 方向拉长的高频噪声，模拟草叶纹理
            float blades = Value(u, v * 0.25f, 128, 13) * 0.6f + Value(u, v * 0.3f, 64, 14) * 0.4f;
            var c = Color.Lerp(new Color(0.10f, 0.22f, 0.05f), new Color(0.30f, 0.42f, 0.10f), big * 0.7f + blades * 0.5f);
            c = Color.Lerp(c, new Color(0.38f, 0.36f, 0.16f), Smooth(0.62f, 0.8f, big) * 0.5f);   // 少量枯黄
            c *= 0.75f + fine * 0.45f;
            c.a = Mathf.Clamp01(0.25f + blades * 0.55f + fine * 0.3f);
            return c;
        }));

        static float RockHeight(float u, float v)
        {
            Worley(u, v, 6, 21, out float f1, out float f2, out float _);
            float crack = Smooth(0.0f, 0.12f, f2 - f1);
            float detail = Fbm(u, v, 16, 4, 22);
            return Mathf.Clamp01(crack * (0.55f + 0.45f * detail) + detail * 0.15f);
        }

        public static Texture2D Rock => s_Rock ? s_Rock : (s_Rock = Make("ch20_rock", (u, v) =>
        {
            Worley(u, v, 6, 21, out float f1, out float f2, out float id);
            float h = RockHeight(u, v);
            float detail = Fbm(u, v, 8, 5, 23);
            var c = Color.Lerp(new Color(0.30f, 0.28f, 0.26f), new Color(0.52f, 0.48f, 0.43f), id * 0.6f + detail * 0.5f);
            c = Color.Lerp(c, new Color(0.42f, 0.33f, 0.24f), Smooth(0.55f, 0.85f, Fbm(u, v, 4, 3, 24)) * 0.6f);  // 锈色斑
            c *= Mathf.Lerp(0.35f, 1f, Smooth(0.0f, 0.5f, h));   // 裂缝更暗
            c.a = h;
            return c;
        }));

        /// 由高度场求法线，按 DXT5nm 布局写入 (1, y, y, x)，与 UnpackNormal 在桌面平台的解码方式一致
        public static Texture2D RockNormal
        {
            get
            {
                if (s_RockNormal) return s_RockNormal;
                var t = NewTex("ch20_rock_normal", true);
                var h = new float[Size * Size];
                for (int y = 0; y < Size; y++)
                    for (int x = 0; x < Size; x++) h[y * Size + x] = RockHeight((x + 0.5f) / Size, (y + 0.5f) / Size);
                var px = new Color[Size * Size];
                const float strength = 6f;
                for (int y = 0; y < Size; y++)
                    for (int x = 0; x < Size; x++)
                    {
                        float dx = h[y * Size + (x + 1) % Size] - h[y * Size + (x - 1 + Size) % Size];
                        float dy = h[((y + 1) % Size) * Size + x] - h[((y - 1 + Size) % Size) * Size + x];
                        var n = new Vector3(-dx * strength, -dy * strength, 1).normalized;
                        px[y * Size + x] = new Color(1, n.y * 0.5f + 0.5f, n.y * 0.5f + 0.5f, n.x * 0.5f + 0.5f);
                    }
                t.SetPixels(px); t.Apply(true, false);
                return s_RockNormal = t;
            }
        }

        public static Texture2D Snow => s_Snow ? s_Snow : (s_Snow = Make("ch20_snow", (u, v) =>
        {
            float n = Fbm(u, v, 4, 5, 31);
            float sparkle = Value(u, v, 128, 32);
            var c = Color.Lerp(new Color(0.70f, 0.76f, 0.86f), new Color(0.93f, 0.95f, 0.98f), n);
            c += Color.white * Smooth(0.92f, 1f, sparkle) * 0.08f;
            c.a = Mathf.Clamp01(0.2f + n * 0.5f);
            return c;
        }));

        public static Texture2D Sand => s_Sand ? s_Sand : (s_Sand = Make("ch20_sand", (u, v) =>
        {
            Worley(u, v, 12, 41, out float f1, out float _, out float id);
            float pebble = 1f - Smooth(0.15f, 0.48f, f1);          // 圆滚滚的卵石
            float grain = Fbm(u, v, 64, 2, 42);
            var sand = Color.Lerp(new Color(0.42f, 0.33f, 0.22f), new Color(0.58f, 0.48f, 0.34f), grain);
            var stone = Color.Lerp(new Color(0.40f, 0.38f, 0.35f), new Color(0.62f, 0.58f, 0.52f), id);
            var c = Color.Lerp(sand, stone, Smooth(0.25f, 0.45f, pebble));
            c.a = Mathf.Clamp01(pebble * 0.85f + grain * 0.15f);
            return c;
        }));
    }
}
