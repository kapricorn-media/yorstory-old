attribute vec2 a_position;
attribute vec2 a_uv;

uniform vec3 u_offsetPos;
uniform vec2 u_scalePos;
uniform vec2 u_offsetUv;
uniform vec2 u_scaleUv;

varying highp vec2 v_uv;

void main()
{
    v_uv = a_uv * u_scaleUv + u_offsetUv;
    vec3 pos = vec3(a_position * u_scalePos, 0) + u_offsetPos;
    gl_Position = vec4(pos, 1.0);
}
