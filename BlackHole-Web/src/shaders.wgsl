
struct CameraUniform {
    resolutionFov: vec4f,
    cameraPosition: vec4f,
    cameraRotation: vec4f,
};

struct OrbitState {
    u: f32,
    duPhi: f32,
};

struct RayOrbit {
    state: OrbitState,
    radialBasis: vec3f,
    tangentBasis: vec3f,
    impactParameter: f32,
};

struct TraceResult {
    hit: bool,
    hitDisk: bool,
    hitPosition: vec3f,
    impactParameter: f32,
    pathAngle: f32,
    escapeDirection: vec3f,
};

@group(0) @binding(0)
var<uniform> camera: CameraUniform;

struct VertexOutput {
    @builtin(position) position: vec4f,
    @location(0) uv: vec2f,
};

// =================================================
// SCHWARZSCHILD ORBIT EQUATIONS
// =================================================

fn orbitDerivative(
    state: OrbitState,
    schwarzschildRadius: f32
) -> OrbitState {

    let du = state.duPhi;

    let d2u =
        -state.u +
        1.5 * schwarzschildRadius * state.u * state.u;

    return OrbitState(du, d2u);
}

// =================================================
// INITIALIZE RAY ORBIT
// =================================================

fn initializeOrbit(
    rayOrigin: vec3f,
    rayDirection: vec3f,
    blackHoleCenter: vec3f,
    schwarzschildRadius: f32
) -> RayOrbit {

    let relativePosition = rayOrigin - blackHoleCenter;
    let initialRadius = length(relativePosition);

    let radialBasis = normalize(relativePosition);

    let radialComponent = dot(
        rayDirection,
        radialBasis
    );

    let tangentDirection =
        rayDirection - radialComponent * radialBasis;

    let sinAlpha = length(tangentDirection);

    let orbitNormal = normalize(
        cross(radialBasis, rayDirection)
    );

    let tangentBasis = normalize(
        cross(orbitNormal, radialBasis)
    );

    let metricFactor =
        1.0 - schwarzschildRadius / initialRadius;

    let sqrtMetric = sqrt(metricFactor);

    let impactParameter =
        initialRadius * sinAlpha / sqrtMetric;

    let initialU = 1.0 / initialRadius;

    let initialDuPhi =
        -sqrtMetric * radialComponent /
        (initialRadius * sinAlpha);

    let state = OrbitState(
        initialU,
        initialDuPhi
    );

    return RayOrbit(
        state,
        radialBasis,
        tangentBasis,
        impactParameter
    );
}



fn addOrbitStates(
    state1: OrbitState,
    state2: OrbitState
) -> OrbitState {

    return OrbitState(
        state1.u + state2.u,
        state1.duPhi + state2.duPhi
    );
}

fn scaleOrbitState(
    state: OrbitState,
    scale: f32
) -> OrbitState {

    return OrbitState(
        state.u * scale,
        state.duPhi * scale
    );
}


fn orbitRK4Step(
    state: OrbitState,
    stepSize: f32,
    schwarzschildRadius: f32
) -> OrbitState {

    let k1 = orbitDerivative(
        state,
        schwarzschildRadius
    );

    let k2State = addOrbitStates(
        state,
        scaleOrbitState(k1, stepSize * 0.5)
    );

    let k2 = orbitDerivative(
        k2State,
        schwarzschildRadius
    );

    let k3State = addOrbitStates(
        state,
        scaleOrbitState(k2, stepSize * 0.5)
    );

    let k3 = orbitDerivative(
        k3State,
        schwarzschildRadius
    );

    let k4State = addOrbitStates(
        state,
        scaleOrbitState(k3, stepSize)
    );

    let k4 = orbitDerivative(
        k4State,
        schwarzschildRadius
    );

    let weightedSum = addOrbitStates(
        addOrbitStates(
            k1,
            scaleOrbitState(k2, 2.0)
        ),
        addOrbitStates(
            scaleOrbitState(k3, 2.0),
            k4
        )
    );

    return addOrbitStates(
        state,
        scaleOrbitState(
            weightedSum,
            stepSize / 6.0
        )
    );
}


fn getCameraRay(screen: vec2f) -> vec3f {

    let yaw = camera.cameraRotation.x;
    let pitch = camera.cameraRotation.y;

    let forward = normalize(vec3f(
        cos(pitch) * sin(yaw),
        sin(pitch),
        -cos(pitch) * cos(yaw)
    ));

    let worldUp = vec3f(
        0.0,
        1.0,
        0.0
    );

    let right = normalize(
        cross(forward, worldUp)
    );

    let up = normalize(
        cross(right, forward)
    );

    let tanHalfFov = camera.resolutionFov.z;

    return normalize(
        forward +
        right * screen.x * tanHalfFov +
        up * screen.y * tanHalfFov
    );
}



fn traceBlackHole(
    rayOrigin: vec3f,
    rayDirection: vec3f,
    blackHoleCenter: vec3f,
    schwarzschildRadius: f32,
    diskInnerRadius: f32,
    diskOuterRadius: f32
) -> TraceResult {

    let relativePosition = rayOrigin - blackHoleCenter;
    let initialRadius = length(relativePosition);

    // Camera inside event horizon.
    if (initialRadius <= schwarzschildRadius) {
        return TraceResult(
            true,
            false,
            blackHoleCenter,
            0.0,
            0.0,
            vec3f(0.0)
        );
    }

    let radialBasis = normalize(relativePosition);

    let radialComponent = dot(
        rayDirection,
        radialBasis
    );

    let tangentDirection =
        rayDirection - radialComponent * radialBasis;

    // Handle purely radial rays.
    if (length(tangentDirection) < 0.0001) {

        if (radialComponent < 0.0) {
            return TraceResult(
                true,
                false,
                blackHoleCenter,
                0.0,
                0.0,
                vec3f(0.0)
            );
        }

        return TraceResult(
            false,
            false,
            rayOrigin,
            0.0,
            0.0,
            rayDirection
        );
    }

    let orbit = initializeOrbit(
        rayOrigin,
        rayDirection,
        blackHoleCenter,
        schwarzschildRadius
    );

    let impactParameter = orbit.impactParameter;

    var state = orbit.state;
    var phi = 0.0;

    let stepSize = 0.01;
    let maxSteps = 1000;

    var radius = 1.0 / state.u;

    var radialDirection =
        orbit.radialBasis * cos(phi) +
        orbit.tangentBasis * sin(phi);

    var prevPosition =
        blackHoleCenter + radialDirection * radius;

    for (var i = 0; i < maxSteps; i++) {

        if (state.u <= 0.0) {
            return TraceResult(
                false,
                false,
                vec3f(0.0),
                impactParameter,
                phi,
                vec3f(0.0)
            );
        }

        radius = 1.0 / state.u;

        // Event horizon.
        if (radius <= schwarzschildRadius) {
            return TraceResult(
                true,
                false,
                blackHoleCenter,
                impactParameter,
                phi,
                vec3f(0.0)
            );
        }

        radialDirection =
            orbit.radialBasis * cos(phi) +
            orbit.tangentBasis * sin(phi);

        let currentPosition =
            blackHoleCenter + radialDirection * radius;

        let previousSide =
            prevPosition.y - blackHoleCenter.y;

        let currentSide =
            currentPosition.y - blackHoleCenter.y;

        let crossedDiskPlane =
            (previousSide < 0.0 && currentSide >= 0.0) ||
            (previousSide > 0.0 && currentSide <= 0.0);

        if (i > 0 && crossedDiskPlane) {

            let t =
                previousSide / (previousSide - currentSide);

            let hitPos = mix(
                prevPosition,
                currentPosition,
                t
            );

            let hitPathAngle =
                (phi - stepSize) + t * stepSize;

            let diskRadius = length(
                hitPos.xz - blackHoleCenter.xz
            );

            if (
                diskRadius >= diskInnerRadius &&
                diskRadius <= diskOuterRadius
            ) {

                return TraceResult(
                    false,
                    true,
                    hitPos,
                    impactParameter,
                    hitPathAngle,
                    vec3f(0.0)
                );
            }
        }

        prevPosition = currentPosition;

        state = orbitRK4Step(
            state,
            stepSize,
            schwarzschildRadius
        );

        phi += stepSize;


        if (state.u > 0.0) {

            let nextRadius = 1.0 / state.u;

            if (
                nextRadius > 100.0 &&
                state.duPhi < 0.0
            ) {

                let escapeRadial = normalize(
                    orbit.radialBasis * cos(phi) +
                    orbit.tangentBasis * sin(phi)
                );

                let escapeTangent =
                    -orbit.radialBasis * sin(phi) +
                    orbit.tangentBasis * cos(phi);

                // dr/dphi = -u'/u^2
                let radialDerivative =
                    -state.duPhi / (state.u * state.u);

                // Approximate outgoing direction at large radius.
                let outgoingDirection = normalize(
                    radialDerivative * escapeRadial +
                    nextRadius * escapeTangent
                );

                let escapePosition =
                    blackHoleCenter +
                    escapeRadial * nextRadius;

                return TraceResult(
                    false,
                    false,
                    escapePosition,
                    impactParameter,
                    phi,
                    outgoingDirection
                );
            }
        }
    }

    // Unresolved ray.
    return TraceResult(
        false,
        false,
        blackHoleCenter,
        impactParameter,
        phi,
        vec3f(0.0)
    );
}



@vertex
fn vertexMain(
    @builtin(vertex_index) vertexIndex: u32
) -> VertexOutput {

    var positions = array<vec2f, 3>(
        vec2f(-1.0, -1.0),
        vec2f(3.0, -1.0),
        vec2f(-1.0, 3.0)
    );

    var output: VertexOutput;

    output.position = vec4f(
        positions[vertexIndex],
        0.0,
        1.0
    );

    output.uv = vec2f(
        positions[vertexIndex].x * 0.5 + 0.5,
        0.5 - positions[vertexIndex].y * 0.5
    );

    return output;
}


fn Hash21(p: vec2f) -> f32 {

    return fract(
        sin(dot(p, vec2f(127.1, 311.7))) *
        43758.5453123
    );
}

fn noise2D(p: vec2f) -> f32 {

    let i = floor(p);
    let f = fract(p);

    let a = Hash21(i);
    let b = Hash21(i + vec2f(1.0, 0.0));
    let c = Hash21(i + vec2f(0.0, 1.0));
    let d = Hash21(i + vec2f(1.0, 1.0));

    let u = f * f * (3.0 - 2.0 * f);

    return mix(a, b, u.x) +
        (c - a) * u.y * (1.0 - u.x) +
        (d - b) * u.x * u.y;
}



fn starfield(
    direction: vec3f,
    time: f32
) -> vec3f {

    let d = normalize(direction);

    // Convert direction to spherical coordinates.
    let longitude = atan2(d.z, d.x);

    let latitude = asin(
        clamp(d.y, -1.0, 1.0)
    );

    let uv = vec2f(
        longitude / 6.2831853 + 0.5,
        latitude / 3.14159265 + 0.5
    );

    // Divide the sky into cells.
    let grid = uv * vec2f(640.0, 320.0);

    let cell = floor(grid);
    let local = fract(grid);

    // Decide whether this cell contains a star.
    let starSeed = Hash21(
        cell + vec2f(17.3, 91.7)
    );

    let presence = step(0.992, starSeed);

    // Random star position.
    let starPosition = vec2f(
        Hash21(cell + vec2f(3.1, 7.7)),
        Hash21(cell + vec2f(11.7, 19.3))
    );

    let distanceToStar = length(
        local - starPosition
    );

    // Random star size.
    let sizeSeed = Hash21(
        cell + vec2f(31.4, 8.2)
    );

    let starRadius = mix(
        0.08,
        0.22,
        sizeSeed
    );

    let starShape = 1.0 - smoothstep(
        starRadius * 0.15,
        starRadius,
        distanceToStar
    );

    // Random brightness.
    let brightnessSeed = Hash21(
        cell + vec2f(27.8, 53.2)
    );

    let brightness = mix(
        0.25,
        2.0,
        pow(brightnessSeed, 5.0)
    );

    // Subtle twinkling.
    let phase =
        Hash21(cell + vec2f(71.4, 9.2)) *
        6.2831853;

    let frequency = mix(
        0.5,
        1.8,
        Hash21(cell + vec2f(41.2, 13.5))
    );

    let twinkle =
        0.88 +
        0.12 * sin(time * frequency + phase);

    // Slight star color variation.
    let colorSeed = Hash21(
        cell + vec2f(21.7, 3.4)
    );

    let starColor = mix(
        vec3f(0.62, 0.75, 1.0),
        vec3f(1.0, 0.85, 0.68),
        colorSeed
    );

    let stars =
        presence *
        starShape *
        brightness *
        twinkle;

    let background = vec3f(
        0.0008,
        0.0012,
        0.003
    );

    return background + starColor * stars;
}

@fragment
fn fragmentMain(
    input: VertexOutput
) -> @location(0) vec4f {


    var screen = vec2f(
        input.uv.x * 2.0 - 1.0,
        1.0 - input.uv.y * 2.0
    );

    screen.x *=
        camera.resolutionFov.x /
        camera.resolutionFov.y;


    let rayOrigin = camera.cameraPosition.xyz;

    let rayDirection = getCameraRay(screen);

    

    let schwarzschildRadius = 0.65;

    let criticalImpactParameter =
        2.5980762 * schwarzschildRadius;

    let blackHoleCenter = vec3f(
        0.0,
        0.0,
        -5.0
    );


    let diskInnerRadius = 0.85;
    let diskOuterRadius = 2.2;

    let trace = traceBlackHole(
        rayOrigin,
        rayDirection,
        blackHoleCenter,
        schwarzschildRadius,
        diskInnerRadius,
        diskOuterRadius
    );

    // -----------------------------------------
    // EVENT HORIZON
    // -----------------------------------------

    if (trace.hit) {
        return vec4f(
            0.0,
            0.0,
            0.0,
            1.0
        );
    }

    // =================================================
    // ACCRETION DISK
    // =================================================

    if (trace.hitDisk) {

        let hitPosition = trace.hitPosition;

        let radialDistance = length(
            hitPosition.xz - blackHoleCenter.xz
        );

        let radialFactor = clamp(
            (radialDistance - diskInnerRadius) /
            (diskOuterRadius - diskInnerRadius),
            0.0,
            1.0
        );

        // -----------------------------------------
        // DISK ANGLE
        // -----------------------------------------

        let angle = atan2(
            hitPosition.z - blackHoleCenter.z,
            hitPosition.x - blackHoleCenter.x
        );

        // -----------------------------------------
        // DIFFERENTIAL ROTATION
        // -----------------------------------------

        let time = camera.cameraRotation.z;

        let safeRadius = max(
            radialDistance,
            diskInnerRadius
        );

        // Approximate Keplerian angular velocity.
        let angularVelocity =
            sqrt(0.5 * schwarzschildRadius) /
            pow(safeRadius, 1.5);

        // Animate plasma structures.
        let animatedAngle =
            angle - time * angularVelocity;

        // -----------------------------------------
        // BROAD TURBULENCE
        // -----------------------------------------

        let broadNoise = noise2D(
            vec2f(
                animatedAngle * 6.0,
                radialDistance * 12.0
            )
        );

        // -----------------------------------------
        // FINE TURBULENCE
        // -----------------------------------------

        let fineNoise = noise2D(
            vec2f(
                animatedAngle * 18.0,
                radialDistance * 35.0
            )
        );

        let turbulence = mix(
            broadNoise,
            fineNoise,
            0.5
        );

        let filament = smoothstep(
            0.4,
            0.8,
            turbulence
        );

        let hotness = pow(
            1.0 - radialFactor,
            1.4
        );

        // -----------------------------------------
        // DISK TEMPERATURE COLORS
        // -----------------------------------------

        let outerColor = vec3f(
            0.18,
            0.008,
            0.002
        );

        let middleColor = vec3f(
            1.0,
            0.16,
            0.015
        );

        let innerColor = vec3f(
            1.0,
            0.72,
            0.32
        );

        let baseColor = mix(
            outerColor,
            middleColor,
            hotness
        );

        var diskColor = mix(
            baseColor,
            innerColor,
            pow(hotness, 4.0) * 0.8
        );

        diskColor *= 0.45 + filament * 1.2;

        // -----------------------------------------
        // PHOTON RING CONTRIBUTION
        // -----------------------------------------

        let impactDifference = abs(
            trace.impactParameter -
            criticalImpactParameter
        );

        let relativeImpactDifference =
            impactDifference /
            max(criticalImpactParameter, 0.0001);

        let nearCritical = 1.0 - smoothstep(
            0.005,
            0.05,
            relativeImpactDifference
        );

        let stronglyLensed = smoothstep(
            3.14159,
            6.28318,
            trace.pathAngle
        );

        let photonRing =
            nearCritical * stronglyLensed;

        let ringColor = vec3f(
            1.0,
            0.82,
            0.58
        );

        diskColor = mix(
            diskColor,
            ringColor,
            photonRing * 0.85
        );

        return vec4f(
            diskColor,
            1.0
        );
    }

    // =================================================
    // GRAVITATIONALLY LENSED STARFIELD
    // =================================================

    if (length(trace.escapeDirection) > 0.5) {

        let background = starfield(
            trace.escapeDirection,
            camera.cameraRotation.z
        );

        return vec4f(
            background,
            1.0
        );
    }

    // -----------------------------------------
    // CAPTURED OR UNRESOLVED RAYS
    // -----------------------------------------

    return vec4f(
        0.0,
        0.0,
        0.0,
        1.0
    );
}
