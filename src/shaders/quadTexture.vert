attribute vec2 a_position;
attribute vec2 a_uv;

uniform vec2 u_offsetPos;
uniform vec2 u_scalePos;
uniform vec2 u_offsetUv;
uniform vec2 u_scaleUv;

varying highp vec2 v_uv;

void main()
{
    v_uv = a_uv * u_scaleUv + u_offsetUv;
    vec2 pos = a_position * u_scalePos + u_offsetPos;
    gl_Position = vec4(pos, 0.0, 1.0);
}
