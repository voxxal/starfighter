#version 330
uniform vec2 screenShake;

in vec3 position;
in vec2 texcoord0;
in vec4 tint;
in float sob;

out vec2 uv;
out vec4 Tint;
out float z;

void main() {
    gl_Position = vec4(position.xyz + vec3(screenShake, 0), 1);
    uv = texcoord0;
    Tint = tint;
    z = position.z;
}
