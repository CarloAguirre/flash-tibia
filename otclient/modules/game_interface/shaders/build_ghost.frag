uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

void main()
{
    vec4 source = texture2D(u_Tex0, v_TexCoord);
    if (source.a <= 0.01)
        discard;

    vec3 ghostTint = vec3(0.44, 0.92, 0.66);
    vec3 tinted = mix(source.rgb, ghostTint, 0.24);
    gl_FragColor = vec4(tinted, source.a * 0.46);
}
