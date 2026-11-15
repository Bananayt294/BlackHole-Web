
struct VertexOutput {
    @builtin(position) position: vec4f,
};

@group(0) @binding(0)
var sceneTexture: texture_2d<f32>;

@group(0) @binding(1)
var bloomTexture: texture_2d<f32>;

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

    return output;
}

fn ACESFilm(color: vec3f) -> vec3f {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;

    return clamp(
        (color * (a * color + b)) /
        (color * (c * color + d) + e),
        vec3f(0.0),
        vec3f(1.0)
    );
}

@fragment
fn fragmentMain(
    input: VertexOutput
) -> @location(0) vec4f {

    let pixel = vec2i(input.position.xy);

    // Original HDR scene.
    let sceneColor = textureLoad(
        sceneTexture,
        pixel,
        0
    ).rgb;

    // Blurred highlights.
    let bloomColor = textureLoad(
        bloomTexture,
        pixel,
        0
    ).rgb;

    // Combine scene and bloom.
    let bloomStrength = 0.8;

    let hdrColor = sceneColor + bloomColor * bloomStrength;

    // Tone mapping.
    let mappedColor = ACESFilm(hdrColor);

    // Convert linear output to display-encoded color.
    let finalColor = pow(
        mappedColor,
        vec3f(1.0 / 2.2)
    );

    return vec4f(finalColor, 1.0);
}
