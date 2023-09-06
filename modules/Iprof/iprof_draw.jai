paused := false;
zone_under_cursor:      *Zone;
next_zone_under_cursor: *Zone;
current_graph_window_selected_sample := -1;

set_cursor_screen_coordinates :: (x: s32, y: s32) {
    screen_cursor_x = x;
    screen_cursor_y = y;
}

Graph_Scaling :: struct {
    target:  s64;    // Integer representing a power of two.
    current: float;  // Interpolates to scale_target.

    ease:    float;  // Rate at which we interpolate.
    output_factor: float64;

    SCALE_MAX :: 16;
}

Config :: struct {
    //
    // Here is stuff you need to set in order for iprof to work:
    //

    line_spacing          : s32 = 8;  // 8 is a dummy value. Replace this with the pixel distance between lines.
    font_character_height : s32 = 8;  // 8 is a dummy value. Replace this with the height of your font.

    draw_text:      (x: float, y: float, str: string, color: Vector4)                    = dummy_draw_text;
    text_width:     (s: string) -> float                                                 = dummy_text_width;
    draw_rectangle:  (x0: float, y0: float, x1: float, y1: float, color: Vector4, click: *Click_Result) -> bool = dummy_draw_rectangle;
    draw_line:      (p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, color: Vector4) = dummy_draw_line;

    graph_begin:    (x: float, y: float, width: float, height: float)                    = dummy_graph_begin;
    graph_end:      (x: float, y: float, width: float, height: float)                    = dummy_graph_end;

    //
    // Here is stuff you can set to customize iprof, or else
    // just leave the way it is. You don't have to worry about this stuff
    // until after you have everything working!
    //

    zone_time_precision_digits: s32 = 2;

    title_background_color := Vector4.{.05, .05, .05, .97};
    title_text_color       := Vector4.{.7, .7, .7, 1};

    zone_text_color_cold   := Vector4.{.8, .15, .15, 1};
    zone_text_color_hot    := Vector4.{1, .9, .9, 1};

    header_color_unhilit := Vector4.{.6, .6, .6, 1};
    header_color_hilit   := Vector4.{1, 1, .7, 1};

    bar_color_a := Vector4.{.1, 0, .03, .93};
    bar_color_b := Vector4.{.14, .05, .06, .93};

    selected_bar_whiten_amount := 0.35;

    graph_zone_under_cursor_text_color       := Vector4.{.8, 1, 1, 1};

    graph_zone_under_cursor_background_color := Vector4.{0, 0, .1, .9};
    graph_current_time_marker_color          := Vector4.{1, 1, .9, 1};

    graph_current_time_history_color         := Vector4.{1, .3, .3, .75};
    graph_time_cursor_color                  := Vector4.{1, 1, .9, .5};
    selected_graph_color                     := Vector4.{1, 1, 1, 1};

    text_y_offset : s32 = 0;  // Extra amount above the baseline to add when drawing text.

    graph_colors: [] Vector4;  // If this array is empty, it will be initted on first draw. Otherwise, you can set it.

    user_data: *void;  // Set this to whatever you want.
}


draw_graph :: (sx: float, sy: float, width: float, height: float,
               config: *Config) {

    if !config.graph_colors init_graph_colors(config);

    SAMPLES :: 128;
    MAGNIFICATION_HIER :: 10;
    MAGNIFICATION_SELF :: 50;

    title_bg_color := config.title_background_color;

    width  *= (1 + graph_bigness_t);
    height *= (1 + graph_bigness_t);
    sy -= height;

    config.draw_rectangle(sx, sy, sx + width, sy + height, title_bg_color);

    selected := zone_selected;

    y_scale : float64 = MAGNIFICATION_HIER;
    if displayed_quantity == .SELF_TIME {
        y_scale = MAGNIFICATION_SELF;
    }

    scaling := get_current_graph_scaling();
    y_scale /= scaling.output_factor;

    if !DO_HISTORY return;

    num_frames := SAMPLES;
    h := history_index;
    if num_frames > NUM_FRAME_SLOTS
    num_frames = NUM_FRAME_SLOTS;

    high : float64 = 0.001;
    low  : float64 = 0.00001;

    if displayed_quantity != .SELF_TIME {
        low  *= 10;
        high *= 10;
    }

    now := get_time();
    dt  := cast(float) (now - graph_last_frame_time);
    if graph_last_frame_time == 0 dt = 0;

    graph_last_frame_time = now;

    update_graph_scaling(*graph_scaling_self, dt);
    update_graph_scaling(*graph_scaling_hier, dt);

    BIGNESS_RATE :: 5;
    graph_bigness_t = move_toward(graph_bigness_t, graph_bigness_t_target, dt * BIGNESS_RATE);

    low  *= scaling.output_factor;
    high *= scaling.output_factor;

    get_graph_color :: (config: *Config, zone: *Zone, selected: *Zone) -> Vector4 {
        if zone == selected return config.selected_graph_color;

        assert(config.graph_colors.count != 0);
        index := zone.hash % cast(u64) config.graph_colors.count;

        color := config.graph_colors[index];
        return color;
    }

    cursor_x := cast(float) screen_cursor_x;
    cursor_y := cast(float) screen_cursor_y;

    next_zone_under_cursor = null;

    inside_graph_window := false;
    if cursor_x >= sx && cursor_x <= sx + width &&
        cursor_y >= sy && cursor_y <= sy + height {
            inside_graph_window = true;
        }

    config.graph_begin(sx, sy, width, height);

//    MAX_ZONES_TO_GRAPH :: 5;  // If you only draw some, you miss spikes in others... sigh!

    for *z : zones {
        color := get_graph_color(config, z, selected);

        history := *z.history_hier;
        if displayed_quantity == .SELF_TIME {
            history = *z.history_self;
        }

        graph_proc(z, num_frames, sx, sy, width, height, y_scale, history, color, low, high, cursor_x, cursor_y, config.draw_line);

//        if it_index >= MAX_ZONES_TO_GRAPH break;
    }

    config.graph_end(sx, sy, width, height);

    // @Hack to deal with significant figures.
    // Will be deprecated when we implement this for real!
    limit_significant_digits :: (s_pointer: *string) {
        SIGNIFICANT_DIGITS :: 2;

        s := <<s_pointer;
        for i : 0..s.count-1 {
            if s.data[i] == #char "." {
                for j : i+1 .. s.count-1 {
                    if s.data[j] != #char "0" {
                        max_length := j + SIGNIFICANT_DIGITS;
                        if max_length < s.count - 2 {
                            s.data[max_length]   = #char "m";
                            s.data[max_length+1] = #char "s";
                            s_pointer.count = max_length + 2;
                        }

                        break;
                    }
                }

                break;
            }
        }
    }

    // Draw the timing for the scale of the graph.

    zone_under_cursor = next_zone_under_cursor;
    if zone_under_cursor {
        // Draw the name of the zone and its timing.
        zone := zone_under_cursor;

        milliseconds : float64 = 0;
        if current_graph_window_selected_sample != -1 {
            history := *zone.history_hier;
            if displayed_quantity == .SELF_TIME {
                history = *zone.history_self;
            }

            milliseconds = history.values[current_graph_window_selected_sample] * 1000;
        }

        timing_string := tprint("%ms", milliseconds);

        limit_significant_digits(*timing_string);

        width_top    := config.text_width(zone.name);
        width_bottom := config.text_width(timing_string);
        width        := max(width_top, width_bottom);

        h := cast(float) config.font_character_height;
        xmargin := h / 5;
        ymargin := h / 8;
        x := cursor_x + 2*h;
        y := cursor_y - 10; // - h;

        config.draw_rectangle(x, y, x + width + 2*xmargin, y + h + 2*ymargin, config.graph_zone_under_cursor_background_color);
        bottom_y := y-h - ymargin;
        config.draw_rectangle(x, bottom_y, x + width + 2*xmargin, y, config.graph_zone_under_cursor_background_color); // y so we don't overlap the upper box.
        config.draw_text(x + xmargin, y, zone.name, config.graph_zone_under_cursor_text_color);
        config.draw_text(x + xmargin, y-h, timing_string, config.graph_zone_under_cursor_text_color);
    }

    // Draw the leading rectangle
    extra_y := height * 0.02;

    {
        y0 := sy - extra_y;
        y1 := sy + height + extra_y;

        color := config.graph_current_time_marker_color;
        x := sx + width * (h / cast(float)num_frames);
        config.draw_rectangle(x, y0, x+1, y1, color);

        color.w = 0.8;
        config.draw_rectangle(x+1, y0, x+2, y1, color);
        color.w = 0.5;
        config.draw_rectangle(x-2, y0, x+0, y1, color);
    }

    // Draw the history rectangle

    dx_dsample := width / (num_frames-1);
    if display_frame != 0 {
        index := (history_index - display_frame + NUM_FRAME_SLOTS) % NUM_FRAME_SLOTS;

        x := sx + dx_dsample * index;
        y0 := sy - extra_y*.5;
        y1 := sy + height + extra_y*.5;

        color := config.graph_current_time_history_color;
        config.draw_rectangle(x, y0, x+1, y1, color);
    }

    // Draw the cursor rectangle
    current_graph_window_selected_sample = -1;
    if inside_graph_window {
        index := cast(s64) ((cursor_x - sx + dx_dsample * .5) / dx_dsample);

        if index >= 0 && index <= num_frames {
            x := sx + dx_dsample * index;

            y0 := sy - extra_y;
            y1 := sy + height + extra_y;

            color := config.graph_time_cursor_color;
            config.draw_rectangle(x, y0, x+1, y1, color);
            current_graph_window_selected_sample = index;
        }
    }
}

get_reportmode_str :: (mode: Report_Mode) -> string {
    if #complete mode == {
        case .SELF_TIME; return " Self Time";
        case .HIERARCHICAL_TIME; return " Hierarchical Time";
        case .CALL_COUNT; return " Call Count";
        case .CALL_GRAPH; return " Call Graph";
    }
}

Click_Result :: struct {
    result: enum {
        NONE;
        HEADER;
        MODE;
        ROW;
    }
    row_index: int;
}

draw :: (sx: float, sy: float,
         full_width: float, height: float,
         config: *Config) {

    click : *Click_Result = config.user_data;

    field_width := config.text_width("555555.55");
    name_width  := full_width - field_width * 3;
    plus_width  := config.text_width("+");

    report := create_report();

    title_right_width := config.text_width(report.title_right);

    line_spacing := cast(float) config.line_spacing;

    {
        // Draw the title.

        header_x0 := sx;
        header_x1 := header_x0 + full_width;
        sy += line_spacing;

        // @Cleanup: These hardcoded 2s are bad.
        if config.draw_rectangle(header_x0, sy, header_x1, sy-line_spacing, config.title_background_color, click)
            click.result = .HEADER;

        config.draw_text(sx+2+plus_width/2,                          sy + config.text_y_offset, report.title,       config.title_text_color);
        config.draw_text(header_x1-2-plus_width/2-title_right_width, sy + config.text_y_offset, report.title_right, config.title_text_color);

        k := 1.0;
        sy += k*line_spacing;
        height -= abs(line_spacing)*k;  // @Cast
    }

    o := 0;
    n := report.records.count;

    if report.hilight >= o + n {
        o = report.hilight - n + 1;
    }

    backup_sy := sy;

    // Draw the background colors for the zone data.

    if config.draw_rectangle(sx, sy, sx + full_width, sy - line_spacing, config.title_background_color, click)
        click.result = .MODE;
    sy += line_spacing;

    whiten :: (color: Vector4, amount: float) -> Vector4 {
        result: Vector4;

        result.x = lerp(color.x, 1, amount);
        result.y = lerp(color.y, 1, amount);
        result.z = lerp(color.z, 1, amount);
        result.w = color.w;

        return result;
    }

    max_records := cast(s64) (height / abs(line_spacing) + 0.5);
    Clamp(*n, 0, max_records);

    for i : 0..n-1 {
        color: Vector4 = ---;

        if i & 1 {
            color = config.bar_color_b;
        } else {
            color = config.bar_color_a;
        }

        if i+o == report.hilight
            color = whiten(color, config.selected_bar_whiten_amount);

        y0 := sy;
        y1 := sy - line_spacing;

        if config.draw_rectangle(sx, y0, sx + full_width, y1, color, click) {
            click.result = .ROW;
            click.row_index = i;
        }
        sy += line_spacing;
    }

    sy = backup_sy + config.text_y_offset;

    // Draw current displayed quantity string
    config.draw_text(sx, sy, get_reportmode_str(displayed_quantity), config.header_color_hilit);

    for j : 1..NUM_HEADER-1 {
        color: Vector4 = ---;
        if j == report.hilit_header {
            color = config.header_color_hilit;
        } else {
            color = config.header_color_unhilit;
        }

        if report.header[j] {
            config.draw_text(sx + 24 + name_width + field_width * (j-1) + field_width/2 - config.text_width(report.header[j]), sy, report.header[j], color);
        }
    }

    sy += line_spacing;

    space_width := config.text_width(" ");

    for i : 0..n-1 {
        buf: String_Builder;

        r := *report.records[i+o];

        x := sx + space_width * r.indent + plus_width/2;
        if r.prefix {
            append(*buf, *r.prefix, 1);
        } else {
            x += plus_width;
        }

        // append_string(*buf, r.name);
        append(*buf, r.name);
        if r.number
            // print_to_buffer(*buf, " (%)", r.number);
            print_to_builder(*buf, " (%)", r.number);

        // @Hack: Make a string from String_Buffer without copying.
        // We can do this fine if we know it's less than the size of
        // one block...

        // buf_string := buffer_to_string_without_copy(buf);
        buf_string := builder_to_string(*buf);

        text_color, glow_factor := get_colors(config, cast(float) r.heat);  // glow_factor is currently ignored.

        /*
        if glow_color.w
            config.draw_text(x+2, sy-1, buf_string, glow_color);
        */

        config.draw_text(x + 1, sy, buf_string, text_color);

        for j : 0..NUM_VALUES-1 {
            if r.value_flag & (1 << j) {
                prec := config.zone_time_precision_digits;
                if j == 2   prec = 2;

                // Clear buf and re-use it.
                reset(*buf);

                float_to_string(*buf, xx r.array_aliased_values[j], prec);
                // buf_string := buffer_to_string_without_copy(buf);
                buf_string := builder_to_string(*buf);

                pad := field_width - plus_width - config.text_width(buf_string);
                if r.indent pad += plus_width;

                config.draw_text(sx + pad + name_width + field_width * j, sy, buf_string, text_color);
            }
        }

        sy += line_spacing;
    }
}

graph_select_sample :: () {
    if current_graph_window_selected_sample >= 0 {
        display_frame = history_index - current_graph_window_selected_sample;
        if display_frame < 0 display_frame += NUM_FRAME_SLOTS;

        if zone_under_cursor {
            expanded_zone = zone_under_cursor;
            update_cursor = true;
            // displayed_quantity = .CALL_GRAPH;
        }
    }
}

get_current_graph_scaling :: () -> *Graph_Scaling {
    if displayed_quantity == .SELF_TIME return *graph_scaling_self;
    return *graph_scaling_hier;
}

graph_bigness_t_target: float;

#scope_file

graph_bigness_t: float;
graph_scaling_self : Graph_Scaling;
graph_scaling_hier : Graph_Scaling;
graph_last_frame_time: float64;

screen_cursor_x: s32;
screen_cursor_y: s32;

update_graph_scaling :: (using scaling: *Graph_Scaling, dt: float) {
    rate := 5.0;  // In powers per second.

    f_target := cast(float) target;

    if abs(current - f_target) > 1 { rate *= 2; }

    rate *= sqrt(ease);

    old := current;
    current = move_toward(current, f_target, dt * rate);

    if current == f_target {
        ease = 0;
    } else {
        ease = move_toward(ease, 1, dt * 5.0);
    }

    output_factor = pow(0.5, current);
}


#scope_file
#import "Basic";
#import "Math";

move_toward :: (a: float, b: float, delta: float) -> float {
    if (b > a) {
        a += delta;
        if (a > b) a = b;
        return a;
    } else if (b < a) {
        a -= delta;
        if (a < b) a = b;
        return a;
    }

    return a;
}

// Use factor to compute a glow amount.
get_colors :: (config: *Config, factor: float) -> (text_color: Vector4, glow_factor: float) {
    Clamp(*factor, 0, 1);

    text_color := lerp(config.zone_text_color_cold, config.zone_text_color_hot, factor);

    // Figure out whether to start up the glow as well.
    GLOW_RANGE :: 0.5;
    GLOW_ALPHA_MAX :: 0.5;

    glow_factor := (factor - GLOW_RANGE) / (1 - GLOW_RANGE);
    Clamp(*glow_factor, 0, 1);

    return text_color, glow_factor;
}

float_to_string :: (builder: *String_Builder, num: float, precision: s64) {
    // @Speed: Will want to make sure this float-to-string routine is fast.
    print_to_builder(builder, "%", formatFloat(num, trailing_width=precision));
}

graph_proc :: (zone: *Zone, nsamples: s64, x0: float, y0: float, width: float, height: float, y_scale: float64,
               history: *Zone_History, color: Vector4, low: float64, high: float64, cursor_x: float, cursor_y: float,
              line_proc: (p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, color: Vector4)) {
    values := history.values;

    i0 := 0;
    i1 := nsamples-1;
    while (i0 < i1) && (values[i0] < low)  i0 += 1;
    while (i1 > i0) && (values[i1] < low)  i1 -= 1;

    if i0 >= i1 return;

    dx_dsample := width / (nsamples-1);

    b: float = 1;
    do_caps := false;
    if zone == zone_under_cursor {
        b = 3;
        do_caps = true;
    }

    last:   Vector2 = ---;
    q0, q1: Vector2 = ---;

    for i : i0..i1 {
        x := x0 + i * dx_dsample;

        value : float64 = values[i];
        y := y0 + cast(float) (value * y_scale * height);

        current := make_vector2(x, y);
        if i > i0 {

            // dir   := subtract(current, last);
            dir   := current-last;
            strut := make_vector2(-dir.y, dir.x);
            normalize_or_zero(*strut);
            strut.x *= b;
            strut.y *= b;

            // p0 := add(last, strut);
            // p1 := subtract(last, strut);
            // p2 := subtract(current, strut);
            // p3 := add(current, strut);
            p0 := last+strut;
            p1 := last-strut;
            p2 := current-strut;
            p3 := current+strut;

            line_proc(p0, p1, p2, p3, color);

            xmin := min(p0.x, p1.x);
            xmax := max(p2.x, p3.x);
            ymin := min(p1.y, p2.y);
            ymax := max(p0.y, p3.y);

            if cursor_x >= xmin && cursor_x <= xmax {
                if cursor_y >= ymin && cursor_y <= ymax {
                    // print("'%': cursor %, %  ;  p %, %\n", zone.name, cursor_x, cursor_y, p0, p1);
                    next_zone_under_cursor = zone;
                }
            }

            if do_caps {
                line_proc(q0, q1, p1, p0, color);

                q0 = p3;
                q1 = p2;
            }
        } else {
            q0 = current;
            q1 = current;
        }

        last = current;
    }
}

init_graph_colors :: (config: *Config) {
    NUM_COLORS :: 7;
    colors := NewArray(NUM_COLORS, Vector4, false);  // We just leak this right now. @Leak.

    k := 0.4;
    M := 0.75;
    A := 1.0;  // We don't want lines to poke through each other.

    colors[0] = make_vector4(M, M, k, A);
    colors[1] = make_vector4(M, k, M, A);
    colors[2] = make_vector4(k, M, M, A);
    colors[3] = make_vector4(M, k, k, A);
    colors[4] = make_vector4(k, M, k, A);
    colors[5] = make_vector4(k, k, M, A);
    colors[6] = make_vector4(k, k, k, A);

    config.graph_colors = colors;
}

dummy_draw_text :: (x: float, y: float, str: string, color: Vector4) {
    log_error("draw_text was not set on Config.\n");
}

dummy_text_width :: (s: string) -> float {
    log_error("text_width was not set on Config.\n");
    return 0;
}

dummy_draw_rectangle :: (x0: float, y0: float, x1: float, y1: float, color: Vector4, click: *Click_Result) -> bool {
    log_error("draw_rectangle was not set on Config.\n");
    return false;
}

dummy_draw_line :: (p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, color: Vector4) {
    log_error("draw_line was not set on Config.\n");
}

dummy_graph_begin :: (x: float, y: float, width: float, height: float) {
    log_error("graph_begin was not set on Config.\n");
}

dummy_graph_end :: (x: float, y: float, width: float, height: float) {
    log_error("graph_end was not set on Config.\n");
}
