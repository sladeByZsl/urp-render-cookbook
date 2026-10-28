// 案例 26.1：读取 Volume 的后处理 Feature（对应 Ch26/SaturationFeature.cs + SaturationVolume.cs，不依赖基类）。
import { Material } from '../engine/shader.js';
import { RenderPassEvent } from '../engine/features.js';
import { defineVolume } from './Cookbook.Ch26.PostFeatureBase.js';

//#region volume
// 默认值要等于“无效果”的值：没有任何 Volume 覆盖时，栈里拿到的就是默认值
const VOLUME = 'Cookbook.Ch26.SaturationVolume';
defineVolume(VOLUME, { saturation: 1, contrast: 1 });
const isActive = (v) => v.saturation !== 1 || v.contrast !== 1;
//#endregion

export default class SaturationFeature {
  constructor(engine, data) {
    this.engine = engine;
    this.data = data || {};
    this.passEvent = this.data.passEvent ?? RenderPassEvent.BeforeRenderingPostProcessing;
  }

  async init() {
    const name = (this.data.shader && this.data.shader.shader) || 'Cookbook/Ch26/Saturation';
    this.material = new Material(await this.engine.shaders.get(name));
  }

  //#region add-passes
  addPasses(frame, enqueue) {
    if (!this.material) return;
    // 和 URP 自带后处理保持一致：相机没勾 Post Processing 就不做
    if (!frame.camera.postProcessing) return;
    // 按优先级、权重混合后的 Volume 参数
    const volume = frame.getVolume(VOLUME);
    if (!volume || !isActive(volume)) return;   // 没效果就不入队

    // SaturationPass.Setup：.value 是混合后的最终值
    this.material.setFloat('_Saturation', volume.saturation);
    this.material.setFloat('_Contrast', volume.contrast);
    enqueue(this.passEvent, (fr) => {
      const temp = fr.getTemporaryRT('_Ch26SaturationTemp', fr.width, fr.height);
      fr.blit(fr.cameraColorTexture(), temp, this.material, 0);
      fr.blit(temp.texture, 'camera');
      fr.bindCamera();
    }, 'Ch26 Saturation');
  }
  //#endregion
}
