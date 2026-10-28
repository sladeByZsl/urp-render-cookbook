// 案例 25.2：生命周期探针的网页版（对应 Ch25/LifecycleProbeFeature.cs）。
// 它什么也不画，只把回调顺序打到浏览器控制台（console.debug），用来观察 Feature / Pass 在一帧里被调用的顺序。
import { RenderPassEvent } from '../engine/features.js';

let s_Frame = 0;
const log = (s) => console.debug(`[帧${s_Frame}] ${s}`);

export default class LifecycleProbeFeature {
  constructor(engine, data) {
    this.passEvent = (data && data.passEvent) ?? RenderPassEvent.AfterRenderingOpaques;
    log('Feature.Create');
  }

  addPasses(frame, enqueue) {
    s_Frame++;
    log(`Feature.OnCameraPreCull  camera=${frame.camera.json.name || 'Camera'}`);
    log('Feature.AddRenderPasses');
    frame.requireDepth = true;   // ConfigureInput(ScriptableRenderPassInput.Depth)
    log('Feature.SetupRenderPasses  color=_CameraColorAttachment');
    enqueue(this.passEvent, (fr) => {
      log('  Pass.OnCameraSetup');
      log(`  Pass.Configure  ${fr.width}x${fr.height} msaa=${fr.msaa}`);
      log(`  Pass.Execute  event=${this.passEvent}`);
      log('  Pass.OnCameraCleanup');
    }, 'Ch25 Lifecycle Probe');
  }
}
