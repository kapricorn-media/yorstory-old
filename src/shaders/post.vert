attribute vec2 a_position;
attribute vec2 a_uv;

varying highp vec2 v_uv;

void main()
{
    v_uv = a_uv;
    gl_Position = vec4(a_position * 2.0 - vec2(1.0, 1.0), 0.0, 1.0);
}
