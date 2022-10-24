precision mediump float;

varying highp vec2 v_uv;

uniform sampler2D u_sampler;
uniform vec4 u_color;
uniform float u_borderRadius;

void main()
{
    gl_FragColor = texture2D(u_sampler, v_uv) * u_color;
}
