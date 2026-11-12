struct CameraUniform {
    resolutionFov: vec4f,
    cameraPosition: vec4f,
    cameraRotation: vec4f,
};

struct Orbitstate{
    u: f32,
    duPhi: f32,
}

@group(0) @binding(0)
var<uniform> camera: CameraUniform;

struct VertexOutput {
    @builtin(position) position: vec4f,
    @location(0) uv: vec2f,
};

fn orbitDerivative(state: Orbitstate, schwarzschildRadius: f32) -> Orbitstate {
    let du = state.duPhi;
    let d2u = -state.u + 1.5 * schwarzschildRadius * state.u * state.u;
    return Orbitstate(du, d2u);
}

fn getCameraRay(screen: vec2f) -> vec3f {
    let yaw = camera.cameraRotation.x;
    let pitch = camera.cameraRotation.y;
    let forward = normalize(vec3f(
        cos(pitch) * sin(yaw),
        sin(pitch),
        -cos(pitch) * cos(yaw)
    ));
    let worldUp = vec3f(0.0, 1.0, 0.0);
    let right = normalize(cross(forward, worldUp));
    let up = normalize(cross(right, forward));
    let tanHalfFov = camera.resolutionFov.z;
    return normalize(forward + right * screen.x * tanHalfFov + up * screen.y * tanHalfFov);
}

@vertex
fn vertexMain(@builtin(vertex_index) vertexIndex: u32) -> VertexOutput {
    var positions = array<vec2f, 3>(
        vec2f(-1.0, -1.0),
        vec2f( 3.0, -1.0),
        vec2f(-1.0,  3.0)
    );

    var output: VertexOutput;

    output.position = vec4f(positions[vertexIndex], 0.0, 1.0);

    output.uv = vec2f(
        positions[vertexIndex].x * 0.5 + 0.5,
        0.5 - positions[vertexIndex].y * 0.5
    );

    return output;
}



fn intersectSphere(rayOrigin: vec3f, rayDirection: vec3f, sphereCenter: vec3f, sphereRadius: f32) -> f32 {
    let oc = rayOrigin - sphereCenter;
    let a = dot(rayDirection, rayDirection);
    let b = dot(oc, rayDirection);
    let c = dot(oc, oc) - sphereRadius * sphereRadius;
    let discriminant = b * b - a * c;

    if (discriminant < 0.0) {
        return -1.0; // No intersection
    }
    let sqrtDiscriminant = sqrt(discriminant);
    let t1 = (-b - sqrtDiscriminant) / a; 
    let t2 = (-b + sqrtDiscriminant) / a;
    if (t1 > 0.0) {
        return t1; // Return the nearest intersection point
    } else if (t2 > 0.0) {
        return t2; // Return the far intersection point if the nearest is behind the ray origin
    }
    return -1.0; // No intersection
}

fn intersectDisk(rayOrigin: vec3f, rayDirection: vec3f, diskCenter: vec3f, innerRadius: f32, outerRadius: f32) -> f32 {
    if (abs(rayDirection.z) < 0.0001) {
        return -1.0;
    }
    let t = (diskCenter.y - rayOrigin.y) / rayDirection.y;
    if (t < 0.0) {
        return -1.0;
    }
    let hitPosition = rayOrigin + t * rayDirection;
    let radialDistance = length(hitPosition.xz - diskCenter.xz);
    if (radialDistance >= innerRadius && radialDistance <= outerRadius) {
        return t;
    }
    return -1.0;
}

fn Hash21(p: vec2f) -> f32 {
    return fract(sin(dot(p, vec2f(127.1, 311.7))) * 43758.5453123);
}

fn noise2D(p: vec2f) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let a = Hash21(i);
    let b = Hash21(i + vec2f(1.0, 0.0));
    let c = Hash21(i + vec2f(0.0, 1.0));
    let d = Hash21(i + vec2f(1.0, 1.0));
    let u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

@fragment
fn fragmentMain(input: VertexOutput) -> @location(0) vec4f {

    // Generate camera ray.
    var screen = vec2f(
    input.uv.x * 2.0 - 1.0,
    1.0 - input.uv.y * 2.0
);

    screen.x *= camera.resolutionFov.x / camera.resolutionFov.y;

    let rayOrigin = camera.cameraPosition.xyz;
    let rayDirection = getCameraRay(screen);


    // Black hole properties.
    let blackHoleCenter = vec3f(0.0, 0.0, -5.0);
    let eventHorizonRadius = 0.65;

    // Accretion disk properties.
    let diskInnerRadius = 0.85;
    let diskOuterRadius = 2.2;

    // Test intersections.
    let tHorizon = intersectSphere(
        rayOrigin,
        rayDirection,
        blackHoleCenter,
        eventHorizonRadius
    );

    let tDisk = intersectDisk(
        rayOrigin,
        rayDirection,
        blackHoleCenter,
        diskInnerRadius,
        diskOuterRadius
    );

    // Is the event horizon the closest hit?
    
if (
    tHorizon > 0.0 &&
    (tDisk < 0.0 || tHorizon < tDisk)
) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
}

    // Is the accretion disk the closest hit?
    if (tDisk > 0.0) {

        let hitPosition = rayOrigin + tDisk * rayDirection;

        let radialDistance = length(
            hitPosition.xy - blackHoleCenter.xy
        );

        let radialFactor = clamp(
            (radialDistance - diskInnerRadius) /
            (diskOuterRadius - diskInnerRadius),
            0.0,
            1.0
        );
        let angle = atan2(hitPosition.z - blackHoleCenter.z, hitPosition.x - blackHoleCenter.x);
        let broadNoise = noise2D(vec2f(angle * 6.0, radialDistance * 12.0));
        let fineNoise = noise2D(vec2f(angle * 18.0, radialDistance * 35.0));
        let turbulence = mix(broadNoise, fineNoise, 0.5);
        let filament = smoothstep(0.4, 0.8, turbulence);
        let hotness = pow(1.0 - radialFactor, 1.4);

        let outerColor = vec3f(0.18, 0.008, 0.002);
        let middleColor = vec3f(1.0, 0.16, 0.015);
        let innerColor = vec3f(1.0, 0.72, 0.32);

        let baseColor = mix(outerColor, middleColor, hotness);
        // Hot inner region, cooler outer region.
        var diskColor = mix(
            baseColor,
            innerColor,
            pow(hotness, 4.0) * 0.8
        );
        diskColor *= 0.45 + filament * 1.2;
        return vec4f(diskColor, 1.0);
    }

    // Nothing was hit: show the background.
    return vec4f(0.0, 0.0, 0.0, 1.0);
}
