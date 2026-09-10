varying vec2 v_TexCoord;
uniform vec4 u_Color;
uniform sampler2D u_Tex0;

void main()
{
    // The external texture is only used as a drawable carrier.  The visual itself
    // is generated procedurally so no trace of the old Ki animation remains.
    vec2 p = v_TexCoord - vec2(0.5, 0.5);
    p.y *= 1.18;

    float d = length(p);

    // Soft elliptical ring with a very faint inner haze.
    float outer = 1.0 - smoothstep(0.34, 0.52, d);
    float inner = smoothstep(0.14, 0.30, d);
    float ring = outer * inner;
    float haze = (1.0 - smoothstep(0.05, 0.48, d)) * 0.16;

    float alpha = clamp((ring * 0.46) + haze, 0.0, 0.50);
    if (alpha < 0.01)
        discard;

    // Cool blue-violet halo: subtle enough to read as magical ambience rather
    // than an attack/energy animation.
    vec3 violet = vec3(0.34, 0.24, 0.88);
    vec3 blue = vec3(0.38, 0.66, 1.00);
    vec3 color = mix(violet, blue, clamp(0.25 + d * 1.25, 0.0, 1.0));

    gl_FragColor = vec4(color, alpha) * u_Color;
}
