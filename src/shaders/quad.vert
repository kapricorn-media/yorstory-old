attribute vec2 a_position;
attribute vec2 a_uv;

uniform vec2 u_offset;
uniform vec2 u_scale;

varying highp vec2 v_uv;

void main()
{
    v_uv = a_uv;
    vec2 pos = a_position * u_scale + u_offset;
    gl_Position = vec4(pos, 0.0, 1.0);
}
