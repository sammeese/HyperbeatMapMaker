shader_type canvas_item;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

// Bloom
uniform bool enable_bloom = false;
uniform float bloom_intensity : hint_range(0.0, 5.0) = 0.7;
uniform float bloom_threshold : hint_range(0.0, 1.0) = 0.8;
uniform float bloom_spread : hint_range(1.0, 30.0) = 15.0;

// CRT Effects
uniform bool enable_crt = false;
uniform float crt_curvature : hint_range(3.0, 10.0) = 6.0;
uniform float scanline_intensity : hint_range(0.0, 1.0) = 0.3;
uniform float scanline_count : hint_range(100.0, 1000.0) = 400.0;
uniform float vignette_intensity : hint_range(0.0, 1.0) = 0.4;
uniform float chromatic_aberration : hint_range(0.0, 0.05) = 0.002;

// VHS Effects
uniform bool enable_vhs = false;
uniform float vhs_distortion : hint_range(0.0, 1.0) = 0.3;
uniform float vhs_noise : hint_range(0.0, 1.0) = 0.15;
uniform float vhs_line_speed : hint_range(0.0, 10.0) = 2.0;

// Color Effects
uniform bool enable_color_grading = false;
uniform vec3 color_tint : source_color = vec3(1.0, 0.6, 0.9); // Vaporwave pink/purple
uniform float color_saturation : hint_range(0.0, 3.0) = 1.5;
uniform float color_contrast : hint_range(0.0, 3.0) = 1.2;

// Posterization / Bit Crush
uniform bool enable_posterize = false;
uniform float color_steps : hint_range(2.0, 32.0) = 16.0;

// Pixelation
uniform bool enable_pixelate = false;
uniform float pixel_size : hint_range(1.0, 6.0) = 2.0;

// Film Grain
uniform bool enable_grain = false;
uniform float grain_intensity : hint_range(0.0, 1.0) = 0.15;

// Glitch
uniform bool enable_glitch = false;
uniform float glitch_intensity : hint_range(0.0, 1.0) = 0.3;

// Hue Shift
uniform bool enable_hue_shift = false;
uniform float hue_shift_speed : hint_range(0.0, 2.0) = 0.5;

// Time uniform for animations
uniform float time = 0.0;

// Random function
float random(vec2 co) {
    return fract(sin(dot(co.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

// CRT screen curvature
vec2 curve_screen(vec2 uv, float curve_amount) {
    uv = uv * 2.0 - 1.0;
    vec2 offset = abs(uv.yx) / vec2(curve_amount, curve_amount);
    uv = uv + uv * offset * offset;
    uv = uv * 0.5 + 0.5;
    return uv;
}

// VHS distortion
vec2 vhs_distort(vec2 uv, float intensity) {
    float line = floor(uv.y * 50.0);
    float offset = sin(line + time * vhs_line_speed) * intensity * 0.01;
    uv.x += offset;
    
    // Random horizontal displacement
    if (random(vec2(line, floor(time))) > 0.95) {
        uv.x += (random(vec2(line, time)) - 0.5) * intensity * 0.05;
    }
    
    return uv;
}

// RGB to HSV
vec3 rgb2hsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

// HSV to RGB
vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void fragment() {
    vec2 uv = SCREEN_UV;
    
    // === PIXELATION ===
    if (enable_pixelate) {
        vec2 pixel_uv = floor(uv * (1.0 / SCREEN_PIXEL_SIZE) / pixel_size) * pixel_size;
        uv = pixel_uv * SCREEN_PIXEL_SIZE;
    }
    
    // === CRT CURVATURE ===
    if (enable_crt) {
        uv = curve_screen(uv, crt_curvature);
        
        // Black out edges if curved off screen
        if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
            COLOR = vec4(0.0, 0.0, 0.0, 1.0);
        }
    }
    
    // === VHS DISTORTION ===
    if (enable_vhs) {
        uv = vhs_distort(uv, vhs_distortion);
    }
    
    // === GLITCH EFFECT ===
    if (enable_glitch) {
        float glitch_line = floor(random(vec2(time * 0.1, 0.0)) * 50.0);
        if (abs(floor(uv.y * 50.0) - glitch_line) < 2.0) {
            uv.x += (random(vec2(glitch_line, time)) - 0.5) * glitch_intensity * 0.1;
        }
    }
    
    // === CHROMATIC ABERRATION ===
    vec4 color;
    if (enable_crt && chromatic_aberration > 0.0) {
        float r = texture(SCREEN_TEXTURE, uv - vec2(chromatic_aberration, 0.0)).r;
        float g = texture(SCREEN_TEXTURE, uv).g;
        float b = texture(SCREEN_TEXTURE, uv + vec2(chromatic_aberration, 0.0)).b;
        color = vec4(r, g, b, 1.0);
    } else {
        color = texture(SCREEN_TEXTURE, uv);
    }
    
    // === BLOOM ===
    vec3 bloom = vec3(0.0);
    if (enable_bloom && bloom_intensity > 0.0) {
        float total_weight = 0.0;
        float sigma = bloom_spread / 3.0;
        
        for (float x = -bloom_spread; x <= bloom_spread; x += 2.0) {
            for (float y = -bloom_spread; y <= bloom_spread; y += 2.0) {
                float dist = length(vec2(x, y));
                if (dist > bloom_spread) continue;
                
                vec2 offset = vec2(x, y) * SCREEN_PIXEL_SIZE;
                vec4 sample_color = texture(SCREEN_TEXTURE, SCREEN_UV + offset);
                
                float brightness = dot(sample_color.rgb, vec3(0.299, 0.587, 0.114));
                vec3 bright = vec3(0.0);
                if (brightness > bloom_threshold) {
                    bright = sample_color.rgb * pow((brightness - bloom_threshold) / (1.0 - bloom_threshold), 2.0);
                }
                
                float weight = exp(-(dist * dist) / (2.0 * sigma * sigma));
                bloom += bright * weight;
                total_weight += weight;
            }
        }
        
        bloom /= total_weight;
        color.rgb += bloom * bloom_intensity;
    }
    
    // === COLOR GRADING ===
    if (enable_color_grading) {
        // Adjust contrast
        color.rgb = (color.rgb - 0.5) * color_contrast + 0.5;
        
        // Adjust saturation
        vec3 hsv = rgb2hsv(color.rgb);
        hsv.y *= color_saturation;
        color.rgb = hsv2rgb(hsv);
        
        // Apply color tint
        color.rgb *= color_tint;
    }
    
    // === POSTERIZATION ===
    if (enable_posterize) {
        color.rgb = floor(color.rgb * color_steps) / color_steps;
    }
    
    // === CRT SCANLINES ===
    if (enable_crt) {
        float scanline = sin(uv.y * scanline_count * 3.14159) * 0.5 + 0.5;
        color.rgb *= 1.0 - (scanline * scanline_intensity);
    }
    
    // === VHS NOISE ===
    if (enable_vhs) {
        float noise = random(uv * time) * vhs_noise;
        color.rgb += vec3(noise);
    }
    
    // === FILM GRAIN ===
    if (enable_grain) {
        float grain = (random(uv * time) - 0.5) * grain_intensity;
        color.rgb += vec3(grain);
    }
    
    // === VIGNETTE ===
    if (enable_crt) {
        vec2 vignette_uv = SCREEN_UV * 2.0 - 1.0;
        float vignette = 1.0 - dot(vignette_uv, vignette_uv) * vignette_intensity;
        color.rgb *= vignette;
    }
    
    // === HUE SHIFT ===
    if (enable_hue_shift) {
        // Convert to HSV, shift hue based on time, convert back to RGB
        vec3 hsv = rgb2hsv(color.rgb);
        hsv.x = fract(hsv.x + time * hue_shift_speed * 0.1); // Cycle through full hue spectrum
        color.rgb = hsv2rgb(hsv);
    }
    
    COLOR = color;
}
