attribute vec2 a_position;

uniform vec2 u_offsetPos;
uniform vec2 u_scalePos;

void main()
{
    vec2 pos = a_position * u_scalePos + u_offsetPos;
    gl_Position = vec4(pos, 0.0, 1.0);
}
