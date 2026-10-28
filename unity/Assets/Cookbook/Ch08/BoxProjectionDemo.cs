// 盒体投影演示：用解析方式生成“站在房间中心看到的” cubemap。
// RoomPattern 与 RoomPattern.hlsl 一一对应：墙在场景里怎么画，cubemap 里就怎么画。
using UnityEngine;

namespace Cookbook.Ch08
{
    public static class BoxProjectionDemo
    {
        public static readonly Vector3 BoxMin = new Vector3(-3, 0, -3);
        public static readonly Vector3 BoxMax = new Vector3(3, 3, 3);

        public static Color RoomPattern(Vector3 p, int face)
        {
            Color c; Vector2 w;
            switch (face)
            {
                case 0: c = new Color(0.85f, 0.42f, 0.18f); w = new Vector2(p.z, p.y); break;
                case 1: c = new Color(0.12f, 0.55f, 0.55f); w = new Vector2(p.z, p.y); break;
                case 2: c = new Color(0.9f, 0.9f, 0.88f); w = new Vector2(p.x, p.z); break;
                case 3: c = new Color(0.08f, 0.08f, 0.09f); w = new Vector2(p.x, p.z); break;
                case 4: c = new Color(0.7f, 0.74f, 0.82f); w = new Vector2(p.x, p.y); break;
                default: c = new Color(0.45f, 0.3f, 0.65f); w = new Vector2(p.x, p.y); break;
            }
            float gx = Mathf.Abs(Frac(w.x + 0.5f) - 0.5f), gy = Mathf.Abs(Frac(w.y + 0.5f) - 0.5f);
            if (Mathf.Min(gx, gy) < 0.025f) c *= 0.3f;
            if (face != 2 && face != 3 && p.y > 1.1f && p.y < 1.4f) c = new Color(1f, 0.97f, 0.9f);
            return c;
        }

        static float Frac(float v) => v - Mathf.Floor(v);

        /// 从 probeCenter 沿 d 射出，求与房间盒体的交点，返回交点处的墙面颜色
        public static Color RoomRadiance(Vector3 probeCenter, Vector3 d)
        {
            float best = float.MaxValue; int face = 0;
            for (int axis = 0; axis < 3; axis++)
            {
                if (Mathf.Abs(d[axis]) < 1e-6f) continue;
                float plane = d[axis] > 0 ? BoxMax[axis] : BoxMin[axis];
                float t = (plane - probeCenter[axis]) / d[axis];
                if (t > 0 && t < best)
                {
                    best = t;
                    face = axis == 0 ? (d.x > 0 ? 0 : 1) : axis == 1 ? (d.y > 0 ? 2 : 3) : (d.z > 0 ? 4 : 5);
                }
            }
            return RoomPattern(probeCenter + d * best, face);
        }
    }
}
