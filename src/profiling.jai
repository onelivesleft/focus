iprof_config := __Iprof.Config.{
    line_spacing = 16,
    font_character_height = 12,
    draw_text = iprof_draw_text,
    text_width = iprof_text_width,
    draw_rectangle = iprof_draw_rectangle,
    graph_begin = iprof_graph_bookend,
    graph_end = iprof_graph_bookend,
    draw_line = iprof_draw_line,
    text_y_offset = -4,
    selected_bar_whiten_amount = 0.1,
};

iprof_show_graph := false;

iprof_text_width :: (text: string) -> float {
    return cast(float)Simp.prepare_text(font_iprof, text);
}

iprof_draw_rectangle :: (x0: float, y0: float, x1: float, y1: float, color: Vector4, click: *__Iprof.Click_Result) -> bool {
    rect := Rect.{x0, window_height - y0, x1-x0, abs(y1-y0)};
    draw_rect(rect, cast,force(Color)color);
    return click && mouse_pointer_is_within(rect);
}

iprof_draw_text :: (x: float, y: float, str: string, color: Vector4) {
    Simp.prepare_text(font_iprof, str);
    Simp.draw_text(font_iprof, cast(s64)x, window_height - cast(s64)y, str, color);
}

iprof_draw_line :: (p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, color: Vector4) {
    draw_line(p0.x, window_height - p0.y, p1.x, window_height - p1.y, color);
    draw_line(p1.x, window_height - p1.y, p2.x, window_height - p2.y, color);
    draw_line(p2.x, window_height - p2.y, p3.x, window_height - p3.y, color);
    //draw_line(p3.x, p3.y, p0.x, p0.y, color);
}

iprof_graph_bookend :: (x: float, y: float, width: float, height: float) { }


iprof_mode_cycle :: () {
    __Iprof.displayed_quantity += 1;
    if __Iprof.displayed_quantity >= .CALL_GRAPH
        __Iprof.displayed_quantity = .SELF_TIME;
}

iprof_up :: () {
    __Iprof.move_cursor(-1);
}

iprof_down :: () {
    __Iprof.move_cursor(+1);
}

iprof_select :: () {
    __Iprof.select();
}

iprof_back :: () {
    __Iprof.select_parent();
}

iprof_pause_recording := false;
iprof_frame_lock :: () {
    iprof_pause_recording = !iprof_pause_recording;
}

iprof_prev_frame :: () {
    iprof_move_frame(-1);
}

iprof_next_frame :: () {
    iprof_move_frame(+1);
}

iprof_move_frame :: (delta: int) {
    __Iprof.move_frame(delta);
}

iprof_click :: (click: __Iprof.Click_Result) {
    if click.result == {
        case .HEADER;   iprof_frame_lock();
        case .MODE;     iprof_mode_cycle();

        case .ROW;
        if __Iprof.displayed_quantity >= .CALL_GRAPH && click.row_index == __Iprof.cursor {
            jump_to_file_coord(__Iprof.expanded_zone.full_path, .{xx (__Iprof.expanded_zone.line - 1), 0});
        }
        else {
            __Iprof.set_cursor(click.row_index);
            iprof_select();
        }
    }
}
