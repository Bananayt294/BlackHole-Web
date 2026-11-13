import shader from "./shaders.wgsl?raw";
import compositeShader from "./composite.wgsl?raw";


const Initialize = async () => {

    const canvas = document.getElementById("gfx-main") as HTMLCanvasElement;

    if (!navigator.gpu) {
        throw new Error("WebGPU is not supported.");
    }

    const adapter = await navigator.gpu.requestAdapter();

    if (!adapter) {
        throw new Error("No GPU adapter found.");
    }

    const device = await adapter.requestDevice();

    const context = canvas.getContext("webgpu");

    if (!context) {
        throw new Error("Failed to get WebGPU context.");
    }

    const width = Math.max(
        1,
        Math.floor(canvas.clientWidth * window.devicePixelRatio)
    );

    const height = Math.max(
        1,
        Math.floor(canvas.clientHeight * window.devicePixelRatio)
    );

    canvas.width = width;
    canvas.height = height;

    const format = navigator.gpu.getPreferredCanvasFormat();

    context.configure({
        device,
        format,
        alphaMode: "opaque"
    });

    const CameraBuffer = device.createBuffer({
        size: 48,
        usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST
    });

    const fov = 60.0 * Math.PI / 180.0;
    const tanHalfFov = Math.tan(fov / 2.0);

    device.queue.writeBuffer(
        CameraBuffer,
        0,
        new Float32Array([
            width, height, tanHalfFov, 0.0,
            0.0, 1.5, 0.0, 0.0,
            0.0, -0.15, 0.0, 0.0
        ])
    );

    const shaderModule = device.createShaderModule({
        code: shader
    });

    const compilationInfo = await shaderModule.getCompilationInfo();

    for (const message of compilationInfo.messages) {
        console.log(
            `Scene WGSL ${message.type} at ${message.lineNum}:${message.linePos}`,
            message.message
        );
    }

    if (compilationInfo.messages.some(m => m.type === "error")) {
        throw new Error("Scene shader compilation failed.");
    }

    const pipeline = device.createRenderPipeline({

        vertex: {
            module: shaderModule,
            entryPoint: "vertexMain"
        },

        fragment: {
            module: shaderModule,
            entryPoint: "fragmentMain",
            targets: [
                { format: "rgba16float" }
            ]
        },

        primitive: {
            topology: "triangle-list"
        },

        layout: "auto"
    });

    const cameraBindGroup = device.createBindGroup({
        layout: pipeline.getBindGroupLayout(0),
        entries: [
            {
                binding: 0,
                resource: {
                    buffer: CameraBuffer
                }
            }
        ]
    });
    const sceneTexture = device.createTexture({
        size: {
            width,
            height
        },

        format: "rgba16float",

        usage:
            GPUTextureUsage.RENDER_ATTACHMENT |
            GPUTextureUsage.TEXTURE_BINDING
    });

    const sceneView = sceneTexture.createView();

    const compositeModule = device.createShaderModule({
        code: compositeShader
    });

    const compositeInfo = await compositeModule.getCompilationInfo();

    for (const message of compositeInfo.messages) {
        console.log(
            `Composite WGSL ${message.type} at ${message.lineNum}:${message.linePos}`,
            message.message
        );
    }

    if (compositeInfo.messages.some(m => m.type === "error")) {
        throw new Error("Composite shader compilation failed.");
    }

    const compositePipeline = device.createRenderPipeline({

        vertex: {
            module: compositeModule,
            entryPoint: "vertexMain"
        },

        fragment: {
            module: compositeModule,
            entryPoint: "fragmentMain",
            targets: [
                { format }
            ]
        },

        primitive: {
            topology: "triangle-list"
        },

        layout: "auto"
    });

    const compositeBindGroup = device.createBindGroup({
        layout: compositePipeline.getBindGroupLayout(0),
        entries: [
            {
                binding: 0,
                resource: sceneView
            }
        ]
    });

    const commandEncoder = device.createCommandEncoder();

    // PASS 1: Render black hole into HDR texture.
    const scenePass = commandEncoder.beginRenderPass({

        colorAttachments: [
            {
                view: sceneView,

                clearValue: {
                    r: 0.0,
                    g: 0.0,
                    b: 0.0,
                    a: 1.0
                },

                loadOp: "clear",
                storeOp: "store"
            }
        ]
    });

    scenePass.setPipeline(pipeline);
    scenePass.setBindGroup(0, cameraBindGroup);
    scenePass.draw(3, 1, 0, 0);
    scenePass.end();

    
    const canvasView = context.getCurrentTexture().createView();

    const displayPass = commandEncoder.beginRenderPass({

        colorAttachments: [
            {
                view: canvasView,

                clearValue: {
                    r: 0.0,
                    g: 0.0,
                    b: 0.0,
                    a: 1.0
                },

                loadOp: "clear",
                storeOp: "store"
            }
        ]
    });

    displayPass.setPipeline(compositePipeline);
    displayPass.setBindGroup(0, compositeBindGroup);
    displayPass.draw(3, 1, 0, 0);
    displayPass.end();

    device.queue.submit([commandEncoder.finish()]);
};

Initialize();
