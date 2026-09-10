varying vec2 v_TexCoord;
uniform vec4 u_Color;
uniform sampler2D u_Tex0;

void main()
{
    vec4 texColor = texture2D(u_Tex0, v_TexCoord);
    if (texColor.a < 0.01)
        discard;

    float luminance = dot(texColor.rgb, vec3(0.299, 0.587, 0.114));
    float glow = clamp(0.35 + luminance * 1.15, 0.0, 1.0);

    // Cool blue-violet tint for Eldera harvest-ready crops.
    vec3 darkViolet = vec3(0.18, 0.12, 0.62);
    vec3 lightViolet = vec3(0.48, 0.58, 1.00);
    vec3 tinted = mix(darkViolet, lightViolet, glow);

    gl_FragColor = vec4(tinted, texColor.a) * u_Color;
}
