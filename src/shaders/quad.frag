precision mediump float;

varying highp vec2 v_uv;

uniform vec4 u_colorTL;
uniform vec4 u_colorTR;
uniform vec4 u_colorBL;
uniform vec4 u_colorBR;

void main()
{
    gl_FragColor = mix(
        mix(u_colorBL, u_colorBR, v_uv.x),
        mix(u_colorTL, u_colorTR, v_uv.x),
        v_uv.y
    );
}
