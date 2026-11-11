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

  const CameraBuffer: GPUBuffer = device.createBuffer({
    size: 16,
    usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST
  });

  
const shaderModule = device.createShaderModule({
    code: shader
});

// Check whether the WGSL shader compiled successfully.
const compilationInfo = await shaderModule.getCompilationInfo();

for (const message of compilationInfo.messages) {
    console.log(
        `WGSL ${message.type} at ${message.lineNum}:${message.linePos}`,
        message.message
    );
}

if (compilationInfo.messages.some(message => message.type === "error")) {
    throw new Error("WGSL shader compilation failed. Check the console.");
}

const pipeline: GPURenderPipeline = device.createRenderPipeline({
    vertex: {
        module: shaderModule,
        entryPoint: "vertexMain"
    },

    fragment: {
        module: shaderModule,
        entryPoint: "fragmentMain",
        targets: [{ format: format }]
    },

    primitive: {
        topology: "triangle-list"
    },

    layout: "auto"
});
const cameraBindGroup: GPUBindGroup = device.createBindGroup({
    layout: pipeline.getBindGroupLayout(0),
    entries: [{
      binding: 0,
      resource: {
        buffer: CameraBuffer
      }
    }]
  });
  const width = Math.max(1,  Math.floor(canvas.clientWidth * window.devicePixelRatio));
  const height = Math.max(1, Math.floor(canvas.clientHeight * window.devicePixelRatio));
  canvas.width = width;
  canvas.height = height;
  const fov = 60.0 * Math.PI/180.0;
  const tanHalfFov = Math.tan(fov / 2.0);
  device.queue.writeBuffer(CameraBuffer, 0, new Float32Array([width, height, tanHalfFov, 0.0 ]));
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
  renderPass.setBindGroup(0, cameraBindGroup);
  renderPass.draw(3, 1, 0, 0);
  renderPass.end();

  device.queue.submit([commandEncoder.finish()]);
}

Initialize();