struct VertexOutput {
    @builtin(position) position: vec4f,
};

@group(0) @binding(0)
var sceneTexture: texture_2d<f32>;

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
fn fragmentMain(input: VertexOutput) -> @location(0) vec4f {
    let pixel = vec2i(input.position.xy);

    return textureLoad(
        sceneTexture,
        pixel,
        0
    );
}