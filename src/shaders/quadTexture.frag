precision mediump float;

varying highp vec2 v_uv;

uniform sampler2D u_sampler;
uniform vec4 u_color;
uniform float u_borderRadius;

void main()
{
    vec4 texColor = texture2D(u_sampler, v_uv);
    // texColor.rgb = texColor.rgb * texColor.a;
    gl_FragColor = texColor * u_color;
    // gl_FragColor.rgb = gl_FragColor.rgb * gl_FragColor.a;
}
