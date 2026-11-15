
import shader from "./shaders.wgsl?raw";
import compositeShader from "./composite.wgsl?raw";
import brightPassShader from "./brightpass.wgsl?raw";
import blurShader from "./blur.wgsl?raw";

const Initialize = async () => {

    const canvas = document.getElementById("gfx-main");

    if (!(canvas instanceof HTMLCanvasElement)) {
        throw new Error("Canvas element gfx-main not found.");
    }

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

    
    type Vec3 = [number, number, number];

    const cameraState = {
        position: [0.0, 1.5, 0.0] as Vec3,
        yaw: 0.0,
        pitch: -Math.atan2(1.5, 5.0)
    };

    const pressedKeys = new Set<string>();

    const mouseSensitivity = 0.002;
    const normalSpeed = 3.0;
    const fastSpeed = 8.0;


    canvas.addEventListener("click", () => {
        if (document.pointerLockElement !== canvas) {
            void canvas.requestPointerLock();
        }
    });

    document.addEventListener("pointerlockchange", () => {
        if (document.pointerLockElement !== canvas) {
            pressedKeys.clear();
        }
    });

    document.addEventListener("mousemove", (event) => {

        if (document.pointerLockElement !== canvas) {
            return;
        }

        cameraState.yaw += event.movementX * mouseSensitivity;
        cameraState.pitch -= event.movementY * mouseSensitivity;

        cameraState.pitch = Math.max(
            -1.54,
            Math.min(1.54, cameraState.pitch)
        );
    });

    const movementKeys = new Set([
        "KeyW",
        "KeyA",
        "KeyS",
        "KeyD",
        "KeyQ",
        "KeyE",
        "ShiftLeft",
        "ShiftRight"
    ]);

    window.addEventListener("keydown", (event) => {

        if (document.pointerLockElement !== canvas) {
            return;
        }

        if (movementKeys.has(event.code)) {
            event.preventDefault();
            pressedKeys.add(event.code);
        }
    });

    window.addEventListener("keyup", (event) => {
        pressedKeys.delete(event.code);
    });

    window.addEventListener("blur", () => {
        pressedKeys.clear();
    });

        function updateCamera(deltaTime: number) {

            const yaw = cameraState.yaw;
            const pitch = cameraState.pitch;

            const forward: Vec3 = [
                Math.cos(pitch) * Math.sin(yaw),
                Math.sin(pitch),
                -Math.cos(pitch) * Math.cos(yaw)
            ];

            const right: Vec3 = [
                Math.cos(yaw),
                0.0,
                Math.sin(yaw)
            ];

            const forwardInput = Number(pressedKeys.has("KeyW")) - Number(pressedKeys.has("KeyS"));

            const rightInput = Number(pressedKeys.has("KeyD")) - Number(pressedKeys.has("KeyA"));

            const verticalInput = Number(pressedKeys.has("KeyE")) - Number(pressedKeys.has("KeyQ"));

            let moveX = forward[0] * forwardInput + right[0] * rightInput;

            let moveY = forward[1] * forwardInput + verticalInput;

            let moveZ = forward[2] * forwardInput + right[2] * rightInput;

            const magnitude = Math.hypot(moveX, moveY, moveZ);

            if (magnitude < 0.0001) {
                return;
            }

            moveX /= magnitude;
            moveY /= magnitude;
            moveZ /= magnitude;

            const speed =
                pressedKeys.has("ShiftLeft") ||
                pressedKeys.has("ShiftRight")
                    ? fastSpeed
                    : normalSpeed;

            let x = cameraState.position[0] + moveX * speed * deltaTime;
            let y = cameraState.position[1] + moveY * speed * deltaTime;
            let z = cameraState.position[2] + moveZ * speed * deltaTime;

            const blackHoleCenter: Vec3 = [0.0, 0.0, -5.0];

            const minimumRadius = 0.65 * 1.2;

            const offsetX = x - blackHoleCenter[0];
            const offsetY = y - blackHoleCenter[1];
            const offsetZ = z - blackHoleCenter[2];

            const distance = Math.hypot(
                offsetX,
                offsetY,
                offsetZ
            );

            if (distance < minimumRadius) {

                let nx: number;
                let ny: number;
                let nz: number;

                if (distance > 0.0001) {

                    nx = offsetX / distance;
                    ny = offsetY / distance;
                    nz = offsetZ / distance;

                } else {

                    const oldX = cameraState.position[0] - blackHoleCenter[0];
                    const oldY = cameraState.position[1] - blackHoleCenter[1];
                    const oldZ = cameraState.position[2] - blackHoleCenter[2];

                    const oldDistance = Math.hypot(oldX, oldY, oldZ);

                    nx = oldDistance > 0.0001 ? oldX / oldDistance : 0.0;
                    ny = oldDistance > 0.0001 ? oldY / oldDistance : 0.0;
                    nz = oldDistance > 0.0001 ? oldZ / oldDistance : 1.0;
                }

                x = blackHoleCenter[0] + nx * minimumRadius;
                y = blackHoleCenter[1] + ny * minimumRadius;
                z = blackHoleCenter[2] + nz * minimumRadius;
            }

            cameraState.position = [x, y, z];
        }

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

            entries: [{
                binding: 0,
                resource: {
                    buffer: CameraBuffer
                }
            }]
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

        const brightTexture = device.createTexture({

            size: {
                width,
                height
            },

            format: "rgba16float",

            usage:
                GPUTextureUsage.RENDER_ATTACHMENT |
                GPUTextureUsage.TEXTURE_BINDING
        });

        const brightView = brightTexture.createView();

        const blurTextureA = device.createTexture({

            size: {
                width,
                height
            },

            format: "rgba16float",

            usage:
                GPUTextureUsage.RENDER_ATTACHMENT |
                GPUTextureUsage.TEXTURE_BINDING
        });

        const blurViewA = blurTextureA.createView();

        const blurTextureB = device.createTexture({

            size: {
                width,
                height
            },

            format: "rgba16float",

            usage:
                GPUTextureUsage.RENDER_ATTACHMENT |
                GPUTextureUsage.TEXTURE_BINDING
        });

        const blurViewB = blurTextureB.createView();

        const brightModule = device.createShaderModule({
            code: brightPassShader
        });

        const brightInfo = await brightModule.getCompilationInfo();

        for (const message of brightInfo.messages) {
            console.log(
                `Bright-pass WGSL ${message.type} at ${message.lineNum}:${message.linePos}`,
                message.message
            );
        }

        if (brightInfo.messages.some(m => m.type === "error")) {
            throw new Error("Bright-pass shader compilation failed.");
        }

        const brightPipeline = device.createRenderPipeline({

            vertex: {
                module: brightModule,
                entryPoint: "vertexMain"
            },

            fragment: {
                module: brightModule,
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

        const brightBindGroup = device.createBindGroup({

            layout: brightPipeline.getBindGroupLayout(0),

            entries: [{
                binding: 0,
                resource: sceneView
            }]
        });

        const blurModule = device.createShaderModule({
            code: blurShader
        });

        const blurInfo = await blurModule.getCompilationInfo();

        for (const message of blurInfo.messages) {
            console.log(
                `Blur WGSL ${message.type} at ${message.lineNum}:${message.linePos}`,
                message.message
            );
        }

        if (blurInfo.messages.some(m => m.type === "error")) {
            throw new Error("Blur shader compilation failed.");
        }

        const blurPipeline = device.createRenderPipeline({

            vertex: {
                module: blurModule,
                entryPoint: "vertexMain"
            },

            fragment: {
                module: blurModule,
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

        const horizontalBlurBuffer = device.createBuffer({
            size: 16,
            usage: GPUBufferUsage.UNIFORM |
                GPUBufferUsage.COPY_DST
        });

        device.queue.writeBuffer(
            horizontalBlurBuffer,
            0,
            new Int32Array([1, 0, 0, 0])
        );

        // Vertical direction: (0, 1).
        const verticalBlurBuffer = device.createBuffer({
            size: 16,
            usage: GPUBufferUsage.UNIFORM |
                GPUBufferUsage.COPY_DST
        });

        device.queue.writeBuffer(
            verticalBlurBuffer,
            0,
            new Int32Array([0, 1, 0, 0])
        );

        const horizontalBlurBindGroup = device.createBindGroup({

            layout: blurPipeline.getBindGroupLayout(0),

            entries: [
                {
                    binding: 0,
                    resource: brightView
                },
                {
                    binding: 1,
                    resource: {
                        buffer: horizontalBlurBuffer
                    }
                }
            ]
        });

        
        const verticalBlurBindGroup = device.createBindGroup({

            layout: blurPipeline.getBindGroupLayout(0),

            entries: [
                {
                    binding: 0,
                    resource: blurViewA
                },
                {
                    binding: 1,
                    resource: {
                        buffer: verticalBlurBuffer
                    }
                }
            ]
        });

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

        // Display the final blurred texture.
        const compositeBindGroup = device.createBindGroup({

            layout: compositePipeline.getBindGroupLayout(0),

            entries: [{
                binding: 0,
                resource: sceneView
            },
            {
                binding: 1,
                resource: blurViewB
            }
        ]
        });

    let previousFrameTime = 0;

    const renderFrame = (timestamp: number) => {

        // Calculate frame delta time.
        const deltaTime = previousFrameTime === 0
            ? 0
            : Math.min((timestamp - previousFrameTime) / 1000, 0.05);

        previousFrameTime = timestamp;

        // Update camera movement.
        updateCamera(deltaTime);

        // Upload updated camera data to GPU.
        device.queue.writeBuffer(
            CameraBuffer,
            0,
            new Float32Array([
                width, height, tanHalfFov, 0.0,

                cameraState.position[0],
                cameraState.position[1],
                cameraState.position[2],
                0.0,

                cameraState.yaw,
                cameraState.pitch,
                timestamp * 0.001,
                0.0
            ])
        );

        const commandEncoder = device.createCommandEncoder();

        const scenePass = commandEncoder.beginRenderPass({
            colorAttachments: [{
                view: sceneView,
                clearValue: {
                    r: 0,
                    g: 0,
                    b: 0,
                    a: 1
                },
                loadOp: "clear",
                storeOp: "store"
            }]
        });

        scenePass.setPipeline(pipeline);
        scenePass.setBindGroup(0, cameraBindGroup);
        scenePass.draw(3, 1, 0, 0);
        scenePass.end();

        const brightPass = commandEncoder.beginRenderPass({
            colorAttachments: [{
                view: brightView,
                clearValue: {
                    r: 0,
                    g: 0,
                    b: 0,
                    a: 1
                },
                loadOp: "clear",
                storeOp: "store"
            }]
        });

        brightPass.setPipeline(brightPipeline);
        brightPass.setBindGroup(0, brightBindGroup);
        brightPass.draw(3, 1, 0, 0);
        brightPass.end();

        const horizontalPass = commandEncoder.beginRenderPass({
            colorAttachments: [{
                view: blurViewA,
                clearValue: {
                    r: 0,
                    g: 0,
                    b: 0,
                    a: 1
                },
                loadOp: "clear",
                storeOp: "store"
            }]
        });

        horizontalPass.setPipeline(blurPipeline);
        horizontalPass.setBindGroup(0, horizontalBlurBindGroup);
        horizontalPass.draw(3, 1, 0, 0);
        horizontalPass.end();

        const verticalPass = commandEncoder.beginRenderPass({
            colorAttachments: [{
                view: blurViewB,
                clearValue: {
                    r: 0,
                    g: 0,
                    b: 0,
                    a: 1
                },
                loadOp: "clear",
                storeOp: "store"
            }]
        });

        verticalPass.setPipeline(blurPipeline);
        verticalPass.setBindGroup(0, verticalBlurBindGroup);
        verticalPass.draw(3, 1, 0, 0);
        verticalPass.end();

        const canvasView = context.getCurrentTexture().createView();

        const displayPass = commandEncoder.beginRenderPass({
            colorAttachments: [{
                view: canvasView,
                clearValue: {
                    r: 0,
                    g: 0,
                    b: 0,
                    a: 1
                },
                loadOp: "clear",
                storeOp: "store"
            }]
        });

        displayPass.setPipeline(compositePipeline);
        displayPass.setBindGroup(0, compositeBindGroup);
        displayPass.draw(3, 1, 0, 0);
        displayPass.end();

        // Submit all five passes.
        device.queue.submit([
            commandEncoder.finish()
        ]);

        // Schedule next frame.
        requestAnimationFrame(renderFrame);
    };

    requestAnimationFrame(renderFrame);

    };

    // START
    Initialize().catch(error => {
        console.error("WebGPU initialization failed:", error);
    });
