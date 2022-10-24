precision mediump float;

varying highp vec2 v_uv;

uniform sampler2D u_sampler;
uniform vec4 u_color;

vec4 gammaCorrect(vec4 color)
{
    float gamma = 2.2;
    return vec4(pow(color.rgb, vec3(1.0 / gamma)), color.a);
}

void main()
{
    gl_FragColor = texture2D(u_sampler, v_uv) * u_color;
}
