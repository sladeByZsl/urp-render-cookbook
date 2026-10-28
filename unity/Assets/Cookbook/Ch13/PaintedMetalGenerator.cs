// 程序化“刷漆金属”套图：一组参数 -> Albedo（sRGB）+ Mask（线性，R 金属 G AO A 光滑）+ Normal（线性）
// 思路：一张 fBm 噪声决定漆皮在哪里剥落；剥落处露出金属，漆皮有厚度（高度差 -> 法线），
// 剥落边缘附近积灰更多（AO 更低、更粗糙）。所有通道都从同一组噪声派生，彼此天然对得上。
using UnityEngine;

namespace Cookbook.Ch13
{
    public static class PaintedMetalGenerator
    {
        //#region settings
        [System.Serializable]
        public struct Settings
        {
            public Color paintColor;      // 漆面颜色（sRGB，美术直觉）
            public Color metalColor;      // 裸金属颜色（sRGB）——金属的 Albedo 就是它的 F0，要亮
            public float wear;            // 剥落程度 0~1
            public float edgeSoftness;    // 剥落边缘的过渡宽度
            public float paintSmoothness; // 漆面光滑度
            public float metalSmoothness; // 裸金属光滑度
            public float paintThickness;  // 漆皮厚度（只影响法线强度）
            public int   seed;
            public int   size;

            public static Settings Default => new Settings
            {
                paintColor = new Color(0.10f, 0.36f, 0.50f), metalColor = new Color(0.78f, 0.78f, 0.80f),
                wear = 0.4f, edgeSoftness = 0.035f, paintSmoothness = 0.55f, metalSmoothness = 0.78f,
                paintThickness = 4f, seed = 7, size = 256
            };
        }
        //#endregion

        public struct Result { public Texture2D albedo, mask, normal; }

        //#region generate
        public static Result Generate(Settings st)
        {
            int N = st.size;
            var chip = new float[N * N];
            var grime = new float[N * N];
            var height = new float[N * N];
            for (int y = 0; y < N; y++)
                for (int x = 0; x < N; x++)
                {
                    float u = (float)x / N, v = (float)y / N;
                    float n = Fbm(u, v, 6, 5, st.seed);           // 剥落形状
                    float g = Fbm(u, v, 16, 4, st.seed + 101);     // 细碎的脏污/磨损
                    // wear 越大，阈值越低，露出的金属越多
                    float t = 1f - st.wear;
                    float c = Mathf.SmoothStep(0f, 1f, Mathf.InverseLerp(t - st.edgeSoftness, t + st.edgeSoftness, n));
                    chip[y * N + x] = c;
                    grime[y * N + x] = g;
                    height[y * N + x] = 1f - c;                    // 漆皮高、裸金属低
                }

            var albedo = new Color[N * N];
            var mask = new Color[N * N];
            var normal = new Color[N * N];
            for (int y = 0; y < N; y++)
                for (int x = 0; x < N; x++)
                {
                    int i = y * N + x;
                    float c = chip[i], g = grime[i];
                    float edge = 4f * c * (1f - c);                // 剥落边缘带：0 → 1 → 0
                    // Albedo：漆面按脏污轻微明暗变化；金属保持明亮（不要把金属画暗）
                    Color paint = st.paintColor * (0.88f + 0.24f * g);
                    Color metal = st.metalColor * (0.92f + 0.12f * g);
                    Color a = Color.Lerp(paint, metal, c);
                    a = Color.Lerp(a, a * 0.8f, edge * 0.5f);      // 边缘积灰略暗
                    albedo[i] = new Color(a.r, a.g, a.b, 1);

                    // Mask：R 金属度（剥落处 = 1）；G AO（边缘/凹处偏暗）；A 光滑度
                    float metallic = c;
                    float ao = Mathf.Clamp01(1f - 0.35f * edge - 0.12f * (1f - g));
                    float smooth = Mathf.Lerp(st.paintSmoothness * (0.85f + 0.3f * g), st.metalSmoothness * (0.9f + 0.1f * g), c);
                    smooth *= 1f - 0.4f * edge;                    // 边缘更粗糙
                    mask[i] = new Color(metallic, ao, 0, Mathf.Clamp01(smooth));

                    // 法线：对高度做中心差分（可平铺，取模回绕）
                    float hL = height[y * N + (x + N - 1) % N], hR = height[y * N + (x + 1) % N];
                    float hD = height[((y + N - 1) % N) * N + x], hU = height[((y + 1) % N) * N + x];
                    var nrm = new Vector3(-(hR - hL) * 0.5f * st.paintThickness, -(hU - hD) * 0.5f * st.paintThickness, 1f).normalized;
                    normal[i] = new Color(nrm.x * 0.5f + 0.5f, nrm.y * 0.5f + 0.5f, nrm.z * 0.5f + 0.5f, 1);
                }

            return new Result
            {
                albedo = Make(albedo, N, false, "PM_Albedo"),   // 颜色贴图：sRGB
                mask   = Make(mask, N, true, "PM_Mask"),        // 数据贴图：线性
                normal = Make(normal, N, true, "PM_Normal"),    // 法线：线性（不能做 sRGB 解码）
            };
        }
        //#endregion

        static Texture2D Make(Color[] px, int n, bool linear, string name)
        {
            var t = new Texture2D(n, n, TextureFormat.RGBA32, true, linear)
            { name = name, wrapMode = TextureWrapMode.Repeat, filterMode = FilterMode.Trilinear, anisoLevel = 4, hideFlags = HideFlags.DontSave };
            t.SetPixels(px);
            t.Apply(true);
            return t;
        }

        // ---- 可平铺的值噪声 fBm：晶格按 period 取模，左右/上下边界无缝 ----
        static float Hash(int x, int y, int seed)
        {
            unchecked
            {
                uint h = (uint)(x * 374761393 + y * 668265263 + seed * 2246822519);
                h = (h ^ (h >> 13)) * 1274126177u;
                return ((h ^ (h >> 16)) & 0xFFFFFF) / 16777215f;
            }
        }
        static float ValueNoise(float u, float v, int period, int seed)
        {
            float x = u * period, y = v * period;
            int x0 = Mathf.FloorToInt(x), y0 = Mathf.FloorToInt(y);
            float fx = x - x0, fy = y - y0;
            fx = fx * fx * (3 - 2 * fx); fy = fy * fy * (3 - 2 * fy);
            int xa = ((x0 % period) + period) % period, xb = (xa + 1) % period;
            int ya = ((y0 % period) + period) % period, yb = (ya + 1) % period;
            float a = Hash(xa, ya, seed), b = Hash(xb, ya, seed), c = Hash(xa, yb, seed), d = Hash(xb, yb, seed);
            return Mathf.Lerp(Mathf.Lerp(a, b, fx), Mathf.Lerp(c, d, fx), fy);
        }
        static float Fbm(float u, float v, int basePeriod, int octaves, int seed)
        {
            float sum = 0, amp = 0.5f, norm = 0;
            for (int o = 0; o < octaves; o++)
            {
                sum += ValueNoise(u, v, basePeriod << o, seed + o * 17) * amp;
                norm += amp; amp *= 0.5f;
            }
            return sum / norm;
        }
    }
}
