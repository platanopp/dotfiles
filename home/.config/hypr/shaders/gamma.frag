// Real gamma correction, applied as a screen shader.
//
// hyprsunset's "gamma" is a linear multiplier on the colour ramp -- it dims
// and brightens. This is the actual curve: out = in^(1/g). Values above 1
// lift the midtones without touching black or white, which is what gamma is
// for and what a brightness slider cannot do.
//
// Written by display_control.py, which substitutes the exponent below.
precision highp float;
varying vec2 v_texcoord;
uniform sampler2D tex;

const float GAMMA = 0.9600;

void main() {
    vec4 c = texture2D(tex, v_texcoord);
    gl_FragColor = vec4(pow(clamp(c.rgb, 0.0, 1.0), vec3(1.0 / GAMMA)), c.a);
}
