precision mediump float;

varying highp vec2 v_pos;
varying highp vec2 v_size;

uniform vec2 u_framePos;
uniform vec2 u_frameSize;
uniform float u_cornerRadius;
uniform vec4 u_color;
uniform vec2 u_screenSize;

bool insideBox(vec2 p, vec2 origin, vec2 size)
{
    return p.x >= origin.x && p.x <= origin.x + size.x && p.y >= origin.y && p.y <= origin.y + size.y;
}

void main()
{
    vec4 color = u_color;
    if (insideBox(gl_FragCoord.xy, u_framePos, u_frameSize)) {
        color.a = 0.0;
    }
    gl_FragColor = color;
}
