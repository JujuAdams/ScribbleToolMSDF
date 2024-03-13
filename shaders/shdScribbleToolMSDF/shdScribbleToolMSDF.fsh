varying vec2 v_vTexcoord;
varying vec4 v_vColour;

float median(vec3 color)
{
	return max(min(color.r, color.g), min(max(color.r, color.g), color.b));
}

void main()
{
    float sdfDistance = median(texture2D(gm_BaseTexture, v_vTexcoord).rgb);
    float range = max(fwidth(sdfDistance), 0.001) / sqrt(2.0);
    float alpha = smoothstep(0.5 - range, 0.5 + range, sdfDistance);   
    gl_FragColor = vec4(1.0, 1.0, 1.0, alpha);
}
