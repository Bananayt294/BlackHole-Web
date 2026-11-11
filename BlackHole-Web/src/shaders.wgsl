struct CameraUniform {
    resolution: vec2f,
    tanHalfFov: f32,
};

@group(0) @binding(0)
var<uniform> camera: CameraUniform;

struct VertexOutput {
    @builtin(position) position: vec4f,
    @location(0) uv: vec2f,
};

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
    let t = (diskCenter.z - rayOrigin.z) / rayDirection.z;
    if (t < 0.0) {
        return -1.0;
    }
    let hitPosition = rayOrigin + t * rayDirection;
    let radialDistance = length(hitPosition.xy - diskCenter.xy);
    if (radialDistance >= innerRadius && radialDistance <= outerRadius) {
        return t;
    }
    return -1.0;
}


@fragment
fn fragmentMain(input: VertexOutput) -> @location(0) vec4f {

    // Generate camera ray.
    var screen = vec2f(
        input.uv.x * 2.0 - 1.0,
        1.0 - input.uv.y * 2.0
    );

    screen.x *= camera.resolution.x / camera.resolution.y;

    let rayDirection = normalize(
        vec3f(
            screen.x * camera.tanHalfFov,
            screen.y * camera.tanHalfFov,
            -1.0
        )
    );

    let rayOrigin = vec3f(0.0, 0.0, 0.0);

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

        // Hot inner region, cooler outer region.
        let diskColor = mix(
            vec3f(1.0, 0.85, 0.4),
            vec3f(0.75, 0.06, 0.015),
            radialFactor
        );

        return vec4f(diskColor, 1.0);
    }

    // Nothing was hit: show the background.
    let rayColor = rayDirection * 0.5 + vec3f(0.5);

    return vec4f(rayColor, 1.0);
}
