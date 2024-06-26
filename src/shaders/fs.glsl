#version 330
uniform sampler2D tex;

in vec2 uv;
in vec4 Tint;
in float z;

out vec4 frag_color;

void main() {
    frag_color = texture(tex, uv) * Tint;
    int colored = int(frag_color.a != 0);
    gl_FragDepth = z * colored + 1 * (1 - colored);
}
