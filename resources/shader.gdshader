shader_type canvas_item;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

uniform float bloom_intensity : hint_range(0.0, 5.0) = 2.0;
uniform float threshold : hint_range(0.0, 1.0) = 0.5;
uniform float bloom_spread : hint_range(1.0, 30.0) = 15.0;

void fragment() {
    vec4 color = texture(SCREEN_TEXTURE, SCREEN_UV);
    
    vec3 bloom = vec3(0.0);
    float total_weight = 0.0;
    
    float sigma = bloom_spread / 3.0;
    
    // Sample in a radius
    for (float x = -bloom_spread; x <= bloom_spread; x += 1.0) {
        for (float y = -bloom_spread; y <= bloom_spread; y += 1.0) {
            float dist = length(vec2(x, y));
            if (dist > bloom_spread) continue; // Skip corners
            
            vec2 offset = vec2(x, y) * SCREEN_PIXEL_SIZE;
            vec4 sample_color = texture(SCREEN_TEXTURE, SCREEN_UV + offset);
            
            // Extract bright pixels
            float brightness = dot(sample_color.rgb, vec3(0.299, 0.587, 0.114));
            vec3 bright = vec3(0.0);
            if (brightness > threshold) {
                bright = sample_color.rgb * pow((brightness - threshold) / (1.0 - threshold), 2.0);
            }
            
            // Apply gaussian weight to ALL samples
            float weight = exp(-(dist * dist) / (2.0 * sigma * sigma));
            bloom += bright * weight;
            total_weight += weight;
        }
    }
    
    bloom /= total_weight;
    
    COLOR.rgb = color.rgb + bloom * bloom_intensity;
    COLOR.a = color.a;
}