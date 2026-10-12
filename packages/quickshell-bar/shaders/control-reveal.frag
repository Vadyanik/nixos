#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    float progress;
} ubuf;
layout(binding = 1) uniform sampler2D source;
void main() {
    vec2 offset = (qt_TexCoord0 - vec2(1.0, 0.0)) * ubuf.size;
    float radius = length(ubuf.size) * ubuf.progress;
    float edge = max(fwidth(length(offset)), 1.0);
    float mask = 1.0 - smoothstep(radius - edge, radius + edge, length(offset));
    fragColor = texture(source, qt_TexCoord0) * ubuf.qt_Opacity * mask;
}
