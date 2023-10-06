#scope_export

Shader :: struct {
    using platform: Shader_Platform;
}

set_projection :: () {
    t := context.simp.texture_render_target;
    if t {
        immediate_set_2d_projection(t.width, t.height);
    } else {
        c := *context.simp.current_window_info;
        immediate_set_2d_projection(c.window_width, c.window_height);
    }
}

set_shader_for_color :: (enable_blend := false) {
    CheckInit();
    shader := ifx enable_blend then *shader_color_with_blend else *shader_color;
    if state.current_shader != shader {
        immediate_set_shader(shader);
        set_projection();
    }
}

set_shader_for_cool :: (time: float, value: float, lightsources: *[]Vector3, lightsource_intensity: float, lightsource_color: Vector4, line_height: float, lightsource_fade_duration: float) {
    CheckInit();
    if state.current_shader != *shader_cool {
        immediate_set_shader(*shader_cool);
        set_projection();
        c := *context.simp.current_window_info;
        loc := glGetUniformLocation(shader_cool.gl_handle, "u_resolution");
        glUniform2f(loc, cast(float)c.window_width, cast(float)c.window_height);
        loc = glGetUniformLocation(shader_cool.gl_handle, "u_time");
        glUniform1f(loc, time);
        loc = glGetUniformLocation(shader_cool.gl_handle, "jiggle");
        glUniform1f(loc, value);
        if lightsources {
            loc = glGetUniformLocation(shader_cool.gl_handle, "lightsource_count");
            glUniform1i(loc, xx lightsources.count);
            loc = glGetUniformLocation(shader_cool.gl_handle, "lightsource_fade_duration");
            glUniform1f(loc, xx lightsource_fade_duration);
            loc = glGetUniformLocation(shader_cool.gl_handle, "lightsources");
            glUniform3fv(loc, xx lightsources.count, xx lightsources.data);
            loc = glGetUniformLocation(shader_cool.gl_handle, "lightsource_color");
            glUniform4f(loc, lightsource_color.x, lightsource_color.y, lightsource_color.z, lightsource_color.w);
            loc = glGetUniformLocation(shader_cool.gl_handle, "lightsource_intensity");
            glUniform1f(loc, lightsource_intensity);
            loc = glGetUniformLocation(shader_cool.gl_handle, "half_line_height");
            glUniform1f(loc, line_height / 2);
        }
        else {
            loc = glGetUniformLocation(shader_cool.gl_handle, "lightsource_count");
            glUniform1i(loc, 0);
        }
    }
}

set_shader_for_cool_rounded_rect :: (value: float) {
    CheckInit();
    if state.current_shader != *shader_cool_rounded_rect {
        immediate_set_shader(*shader_cool_rounded_rect);
        set_projection();
        c := *context.simp.current_window_info;
        loc := glGetUniformLocation(shader_cool_rounded_rect.gl_handle, "u_resolution");
        glUniform2f(loc, cast(float)c.window_width, cast(float)c.window_height);
        loc = glGetUniformLocation(shader_cool_rounded_rect.gl_handle, "u_time");
        glUniform1f(loc, value);
    }
}

set_shader_for_text :: () {
    CheckInit();
    if state.current_shader != *shader_text {
        immediate_set_shader(*shader_text);
        set_projection();
        loc := glGetUniformLocation(shader_text.gl_handle, "lightsource_count");
        glUniform1i(loc, 0);
    }
}

set_shader_for_text :: (lightsources: *[]Vector3, lightsource_intensity: float, lightsource_color: Vector4) {
    CheckInit();
    if state.current_shader != *shader_text {
        immediate_set_shader(*shader_text);
        set_projection();
        loc := glGetUniformLocation(shader_text.gl_handle, "lightsource_count");
        glUniform1i(loc, xx lightsources.count);
        loc = glGetUniformLocation(shader_text.gl_handle, "lightsources");
        glUniform3fv(loc, xx lightsources.count, xx lightsources.data);
        loc = glGetUniformLocation(shader_text.gl_handle, "lightsource_color");
        glUniform4f(loc, lightsource_color.x, lightsource_color.y, lightsource_color.z, lightsource_color.w);
        loc = glGetUniformLocation(shader_text.gl_handle, "lightsource_intensity");
        glUniform1f(loc, lightsource_intensity);
    }
}


set_shader_for_images :: (texture: *Texture) {
    CheckInit();
    immediate_flush();
    if state.current_shader != *shader_sprite {
        immediate_set_shader(*shader_sprite);
        set_projection();
    }

    immediate_set_texture(texture);
}

set_shader_for_rects :: () {
    CheckInit();
    if state.current_shader != *shader_rounded_rect {
        immediate_set_shader(*shader_rounded_rect);
        set_projection();
    }
}

// Not working
set_shader_for_circles :: () {
    CheckInit();
    if state.current_shader != *shader_circle {
        immediate_set_shader(*shader_circle);
        set_projection();
    }
}

shader_sprite: Shader;
shader_text:   Shader;
shader_color:  Shader;
shader_color_with_blend:  Shader;
shader_cool: Shader;
shader_rounded_rect:      Shader;
shader_cool_rounded_rect:      Shader;
shader_circle:            Shader;
