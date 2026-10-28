// 预积分皮肤散射 LUT（Penner 2011）的程序化生成。
// u 轴：N·L 从 -1 到 1；v 轴：曲率 1/r，从 0（平面）到 MaxInvRadius（单位 1/mm）。
// 散射剖面用 d'Eon & Luebke（GPU Gems 3 第 14 章）给出的 6 个高斯之和。
using System.IO;
using UnityEditor;
using UnityEngine;

namespace Cookbook.Ch12
{
    public static class SkinLutBaker
    {
        //#region profile
        // 每个高斯的方差（mm²）与 RGB 权重
        static readonly float[] Variance = { 0.0064f, 0.0484f, 0.187f, 0.567f, 1.99f, 7.41f };
        static readonly Vector3[] Weight =
        {
            new Vector3(0.233f, 0.455f, 0.649f),
            new Vector3(0.100f, 0.336f, 0.344f),
            new Vector3(0.118f, 0.198f, 0.000f),
            new Vector3(0.113f, 0.007f, 0.007f),
            new Vector3(0.358f, 0.004f, 0.000f),
            new Vector3(0.078f, 0.000f, 0.000f),
        };

        // 散射剖面 R(d)：距离入射点 d 毫米处的出射能量
        // 注意归一化用的是一维高斯 1/sqrt(2πv)：我们只沿圆环（一维）积分，
        // 若用二维的 1/(2πv)，宽高斯（红光的长距离散射）会被严重低估
        static Vector3 Profile(float d)
        {
            Vector3 r = Vector3.zero;
            for (int k = 0; k < 6; k++)
            {
                float v = Variance[k];
                float g = Mathf.Exp(-d * d / (2f * v)) / Mathf.Sqrt(2f * Mathf.PI * v);
                r += Weight[k] * g;
            }
            return r;
        }
        //#endregion

        public const float MaxInvRadius = 1.0f;   // v = 1 对应半径 1mm

        //#region integrate
        // 在半径为 r 的圆环上积分：入射点与出射点夹角 x，弦长 2r·sin(x/2)
        // D(θ) = ∫ saturate(cos(θ + x)) R(2r sin(x/2)) dx / ∫ R(2r sin(x/2)) dx
        public static Color Integrate(float cosTheta, float invRadius)
        {
            float theta = Mathf.Acos(Mathf.Clamp(cosTheta, -1f, 1f));
            float r = 1f / Mathf.Max(invRadius, 1e-4f);
            Vector3 num = Vector3.zero, den = Vector3.zero;
            const int Steps = 256;
            float dx = 2f * Mathf.PI / Steps;
            for (int s = 0; s < Steps; s++)
            {
                float x = -Mathf.PI + (s + 0.5f) * dx;
                Vector3 p = Profile(Mathf.Abs(2f * r * Mathf.Sin(x * 0.5f)));
                num += p * Mathf.Max(0f, Mathf.Cos(theta + x));
                den += p;
            }
            return new Color(num.x / den.x, num.y / den.y, num.z / den.z, 1f);
        }
        //#endregion

        //#region generate
        public static Texture2D Generate(int width = 256, int height = 64)
        {
            var tex = new Texture2D(width, height, TextureFormat.RGBAHalf, false, true)   // 半精度 + 线性：暗部不出色带
            {
                name = "SkinLUT", wrapMode = TextureWrapMode.Clamp, filterMode = FilterMode.Bilinear
            };
            var px = new Color[width * height];
            for (int y = 0; y < height; y++)
            {
                float invR = (y + 0.5f) / height * MaxInvRadius;
                for (int x = 0; x < width; x++)
                {
                    float ndl = (x + 0.5f) / width * 2f - 1f;
                    px[y * width + x] = Integrate(ndl, invR);
                }
            }
            tex.SetPixels(px);
            tex.Apply();
            return tex;
        }
        //#endregion

        [MenuItem("Cookbook/Ch12/Bake Skin LUT")]
        static void Bake()
        {
            var tex = Generate();
            const string path = "Assets/Cookbook/Ch12/SkinLUT.png";
            // 存成 PNG 会量化到 8 位，暗部有轻微色带；要求高可改存 EXR（EncodeToEXR）
            var png = new Texture2D(tex.width, tex.height, TextureFormat.RGBA32, false, true);
            png.SetPixels(tex.GetPixels()); png.Apply();
            File.WriteAllBytes(path, png.EncodeToPNG());
            Object.DestroyImmediate(png);
            Object.DestroyImmediate(tex);
            AssetDatabase.ImportAsset(path);
            var imp = (TextureImporter)AssetImporter.GetAtPath(path);
            imp.sRGBTexture = false;              // LUT 是数据，不是颜色
            imp.wrapMode = TextureWrapMode.Clamp;
            imp.mipmapEnabled = false;
            imp.textureCompression = TextureImporterCompression.Uncompressed;
            imp.SaveAndReimport();
            Debug.Log("[Ch12] Skin LUT -> " + path);
        }
    }
}
