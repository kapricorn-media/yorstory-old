attribute vec2 a_position;

uniform vec3 u_offsetPos;
uniform vec2 u_scalePos;

varying highp vec2 v_pos;
varying highp vec2 v_size;

void main()
{
    v_pos = u_offsetPos.xy;
    v_size = u_scalePos;

    vec3 pos = vec3(a_position * u_scalePos, 0) + u_offsetPos;
    gl_Position = vec4(pos, 1.0);
}
