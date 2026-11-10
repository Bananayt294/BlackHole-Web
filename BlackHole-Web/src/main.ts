import shader from "./shaders.wgsl?raw";

const Initialize = async () => {

  const canvas : HTMLCanvasElement | null = document.getElementById("gfx-main") as HTMLCanvasElement;
  const adapter : GPUAdapter = <GPUAdapter>await navigator.gpu?.requestAdapter();
  const device : GPUDevice = <GPUDevice>await adapter?.requestDevice();
  const context : GPUCanvasContext = <GPUCanvasContext>canvas?.getContext("webgpu");
  const format : GPUTextureFormat = "bgra8unorm";
  context.configure({
    device: device,
    format: format,
    alphaMode: "opaque"
  })

  const pipeline: GPURenderPipeline = device.createRenderPipeline({
    vertex: {
      module: device.createShaderModule({code: shader }),
      entryPoint: "vs_main"
    },
    fragment: {
      module: device.createShaderModule({code: shader }),
      entryPoint: "fs_main",
      targets: [{ format: format }]
    },
    primitive: {
      topology: "triangle-list",
    },
    layout: "auto"
  });

  const commandEncoder: GPUCommandEncoder = device.createCommandEncoder();
  const textureView: GPUTextureView = context.getCurrentTexture().createView();
  const renderPass: GPURenderPassEncoder = commandEncoder.beginRenderPass({
    colorAttachments: [{
      view: textureView,
      clearValue: { r: 0.0, g: 0.0, b: 0.0, a: 1.0 },
      loadOp: "clear",
      storeOp: "store",
    }]
  });
  renderPass.setPipeline(pipeline);
  renderPass.draw(3, 1, 0, 0);
  renderPass.end();

  device.queue.submit([commandEncoder.finish()]);
}

Initialize();