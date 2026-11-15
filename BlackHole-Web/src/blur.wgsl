
struct VertexOutput {
    @builtin(position) position: vec4f,
};

struct BlurParams {
    direction: vec2i,
};

@group(0) @binding(0)
var sourceTexture: texture_2d<f32>;

@group(0) @binding(1)
var<uniform> params: BlurParams;

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

@fragment
fn fragmentMain(
    input: VertexOutput
) -> @location(0) vec4f {

    let pixel = vec2i(input.position.xy);
    let dimensions = vec2i(textureDimensions(sourceTexture));
    let maxPixel = dimensions - vec2i(1, 1);

    // Clamp sampling coordinates to texture boundaries.
    let p0 = clamp(pixel, vec2i(0), maxPixel);

    // Gaussian weights.
    var color = textureLoad(
        sourceTexture, p0, 0
    ) * 0.227027;

    color += textureLoad(
        sourceTexture,
        clamp(pixel + params.direction, vec2i(0), maxPixel),
        0
    ) * 0.1945946;

    color += textureLoad(
        sourceTexture,
        clamp(pixel - params.direction, vec2i(0), maxPixel),
        0
    ) * 0.1945946;

    color += textureLoad(
        sourceTexture,
        clamp(pixel + params.direction * 2, vec2i(0), maxPixel),
        0
    ) * 0.1216216;

    color += textureLoad(
        sourceTexture,
        clamp(pixel - params.direction * 2, vec2i(0), maxPixel),
        0
    ) * 0.1216216;

    color += textureLoad(
        sourceTexture,
        clamp(pixel + params.direction * 3, vec2i(0), maxPixel),
        0
    ) * 0.054054;

    color += textureLoad(
        sourceTexture,
        clamp(pixel - params.direction * 3, vec2i(0), maxPixel),
        0
    ) * 0.054054;

    color += textureLoad(
        sourceTexture,
        clamp(pixel + params.direction * 4, vec2i(0), maxPixel),
        0
    ) * 0.016216;

    color += textureLoad(
        sourceTexture,
        clamp(pixel - params.direction * 4, vec2i(0), maxPixel),
        0
    ) * 0.016216;

    return color;
}
