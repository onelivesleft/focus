color_picker_dialog : struct {
    value: float;
    point: Vector2;

    rgba: Vector4;
    hsl:  Vector3;

    recent_color_hash: u64;
    last_drawn_frame_index: u64;

    color_change_callback: #type (rgba: Vector4, hsl: Vector3, update_flags := Color_Picker_Update_Flags.none);
    color_change_callback_data: *void;
}

Color_Picker_Update_Flags :: enum_flags u8 {
    none     :: 0x00;
    live     :: 0x01;
    finalize :: 0x02;
}

Gradient_Mode :: enum u8 {
    // DO NOT CHANGE THESE VALUES (unless you also update the switch statement in the shader)
    red_controlled_2d        :: 0x00;
    green_controlled_2d      :: 0x01;
    blue_controlled_2d       :: 0x02;
    hue_controlled_2d        :: 0x03;
    saturation_controlled_2d :: 0x04;
    lightness_controlled_2d  :: 0x05;

    vertical_1d              :: 0x10;
    red_vertical_1d          :: 0x10;
    green_vertical_1d        :: 0x11;
    blue_vertical_1d         :: 0x12;
    hue_vertical_1d          :: 0x13;
    saturation_vertical_1d   :: 0x14;
    lightness_vertical_1d    :: 0x15;
    alpha_vertical_1d        :: 0x16;

    horizontal_1d            :: 0x20;
    red_horizontal_1d        :: 0x20;
    green_horizontal_1d      :: 0x21;
    blue_horizontal_1d       :: 0x22;
    hue_horizontal_1d        :: 0x23;
    saturation_horizontal_1d :: 0x24;
    lightness_horizontal_1d  :: 0x25;
    alpha_horizontal_1d      :: 0x26;

    checkered_2              :: 0x30;
    checkered_4              :: 0x31;
    palette_entry            :: 0x32;
    solid                    :: 0x33;
    box                      :: 0x34; // `value` determines border width
}

color_picker_set_mode :: (mode: Gradient_Mode) {
    session.color_picker.mode = mode % (Gradient_Mode.lightness_controlled_2d + 1);
    color_picker_set_color(color_picker_dialog.rgba);
}

color_picker_set_value :: (new_value: float, update_flags := Color_Picker_Update_Flags.none) {
    using color_picker_dialog;
    changed := value != new_value;
    value = new_value;

    if session.color_picker.mode == {
        case .red_controlled_2d;
            rgba.x = value;

        case .green_controlled_2d;
            rgba.y = value;

        case .blue_controlled_2d;
            rgba.z = value;

        case .hue_controlled_2d;
            hsl.x = value;
            rgba.xyz = rgb_from_hsl(hsl);

        case .saturation_controlled_2d;
            hsl.y = value;
            rgba.xyz = rgb_from_hsl(hsl);

        case .lightness_controlled_2d;
            hsl.z = value;
            rgba.xyz = rgb_from_hsl(hsl);
    }

    if color_change_callback && (changed || (update_flags & .finalize)) then color_change_callback(rgba, hsl, update_flags);
}

color_picker_set_point :: (new_point: Vector2, update_flags := Color_Picker_Update_Flags.none) {
    using color_picker_dialog;
    changed := new_point != point;
    point = new_point;

    if session.color_picker.mode == {
        case .red_controlled_2d;
            rgba.yz = point;

        case .green_controlled_2d;
            rgba.x = point.x;
            rgba.z = point.y;

        case .blue_controlled_2d;
            rgba.xy = point;

        case .hue_controlled_2d;
            hsl.yz = point;
            rgba.xyz = rgb_from_hsl(hsl);

        case .saturation_controlled_2d;
            hsl.x = point.x;
            hsl.z = point.y;
            rgba.xyz = rgb_from_hsl(hsl);

        case .lightness_controlled_2d;
            hsl.xy = point;
            rgba.xyz = rgb_from_hsl(hsl);
    }

    if color_change_callback && (changed || (update_flags & .finalize)) then color_change_callback(rgba, hsl, update_flags);
}

color_picker_set_alpha :: (alpha: float, update_flags := Color_Picker_Update_Flags.none) {
    using color_picker_dialog;
    changed := rgba.w != alpha;

    rgba.w = alpha;

    if color_change_callback && (changed || (update_flags & .finalize)) then color_change_callback(rgba, hsl, update_flags);
}

color_picker_set_color :: (buffer: *Buffer, range: Offset_Range) {
    s := get_range_as_string(buffer, range);
    rgba, ok := hex_to_color_vec4(s);
    if !ok  return;

    if color_picker_dialog.rgba != rgba then color_picker_set_color(rgba);
}

color_picker_set_color :: (color: Vector4, update_flags := Color_Picker_Update_Flags.none) {
    using color_picker_dialog;
    changed := rgba != color;
    rgba = color;
    hsl = hsl_from_rgb(color.xyz);
    if session.color_picker.mode == {
        case .red_controlled_2d;
            value = rgba.x;
            point = rgba.yz;

        case .green_controlled_2d;
            value = rgba.y;
            point.x = rgba.x;
            point.y = rgba.z;

        case .blue_controlled_2d;
            value = rgba.z;
            point = rgba.xy;

        case .hue_controlled_2d;
            value = hsl.x;
            point = hsl.yz;

        case .saturation_controlled_2d;
            value = hsl.y;
            point.x = hsl.x;
            point.y = hsl.z;

        case .lightness_controlled_2d;
            value = hsl.z;
            point = hsl.xy;
    }

    if color_change_callback && (changed || (update_flags & .finalize)) then color_change_callback(rgba, hsl, update_flags);
}

update_color_picker_recent_color :: (recent_color_hash: u64, color: Vector4) {
    if color_picker_dialog.recent_color_hash != recent_color_hash {
        new_recent_color();
        color_picker_dialog.recent_color_hash = recent_color_hash;
    }
    session.color_picker.recent_colors[0] = color;
}

Color_Change_Buffer_Info :: struct {
    editor_id: s64;
    editor: *Editor;
    buffer: *Buffer;
    range: Offset_Range;
}

color_picker_select_recent_color :: (index: int) {
    using session.color_picker;
    c := recent_colors[index];
    if index > 0 {
        found := false;
        for i : 1 .. recent_colors.count - 1 {
            if recent_colors[i] == .{}  break;
            if recent_colors[i] == recent_colors[0] {
                found = true;
                break;
            }
        }
        if !found  new_recent_color();
    }
    recent_colors[0] = c;
}

color_picker_add_user_color :: (index: int, rgba: Vector4) {
    session.color_picker.user_colors[index] = rgba;
}

color_picker_remove_user_color :: (index: int) {
    session.color_picker.user_colors[index] = .{};
}

color_picker_edit_color_at_cursor :: (editor: *Editor, buffer: *Buffer) {
    start := editor.cursors[editor.main_cursor].pos;
    end := editor.cursors[editor.main_cursor].sel;
    if end - start != 8  return;

    assert(*open_editors[context.current_editor_id] == editor);
    color_picker_current_pick_info = .{context.current_editor_id, editor, buffer, .{start, end}};
}

color_picker_current_pick_info: Color_Change_Buffer_Info;

#scope_file

remove_recent_color :: (index_to_remove: int) {
    using session.color_picker;
    for i : index_to_remove .. recent_colors.count - 2 {
        c := recent_colors[i + 1];
        recent_colors[i] = c;
        if c == .{}  return;
    }
    recent_colors[recent_colors.count - 1] = .{};
}

new_recent_color :: () {
    using session.color_picker;

    for < i : recent_colors.count - 1 .. 1 {
        recent_colors[i] = recent_colors[i - 1];
    }
    recent_colors[0] = .{};
}

