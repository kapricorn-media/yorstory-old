precision mediump float;

varying highp vec2 v_uv;

uniform sampler2D u_sampler;
uniform vec2 u_screenSize;
uniform sampler2D u_lutSampler;

vec3 applyLut(vec3 color, sampler2D lutSampler)
{
    // vec2 blueOffset = vec2(floor(color.b * 8.0) / 8.0, mod(color.b * 8.0, 1.0)); // loquera (OLD)
    vec3 color255 = floor(color * 255.0);
    vec2 blueOffset = vec2(
        mod(color255.b, 16.0) * 256.0,
        floor(color255.b / 16.0) * 256.0
    );
    vec2 pixCoords = blueOffset + vec2(color255.r, color255.g);
    return texture2D(lutSampler, (pixCoords + 0.5) / 4096.0).rgb;
}

void main()
{
    vec2 invScreenSize = 1.0 / u_screenSize;

    vec3 colorCenter = texture2D(u_sampler, v_uv).rgb;
    // vec3 colorLut = applyLut(colorCenter, u_lutSampler);
    vec3 colorLut = colorCenter;
    gl_FragColor = vec4(colorLut, 1.0);
}
