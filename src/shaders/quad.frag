precision mediump float;

varying highp vec2 v_uv;

uniform sampler2D u_sampler;

void main()
{
    gl_FragColor = vec4(0.0, 0.0, 1.0, 1.0);
    gl_FragColor = texture2D(u_sampler, v_uv);
}