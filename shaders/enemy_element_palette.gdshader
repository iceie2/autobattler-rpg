shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D albedo_tex : source_color, hint_default_white;
uniform sampler2D normal_tex : hint_normal;
uniform bool use_normal = false;
uniform vec4 base_color : source_color = vec4(1.0);
uniform vec4 element_color : source_color = vec4(1.0);
uniform float surface_roughness = 0.8;
uniform float surface_metallic = 0.0;
void fragment() {
    vec4 source = texture(albedo_tex, UV) * base_color;
    float value = dot(source.rgb, vec3(0.2126, 0.7152, 0.0722));
    // Keep painted shading/detail; a palette assignment can reach blue from
    // brown where simple multiplication cannot. Original form keeps native PBR.
    ALBEDO = clamp(element_color.rgb * value / 0.32, vec3(0.0), vec3(1.0));
    ROUGHNESS = surface_roughness;
    METALLIC = surface_metallic;
    if (use_normal) { NORMAL_MAP = texture(normal_tex, UV).rgb; }
}
