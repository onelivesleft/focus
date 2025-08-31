debugger : struct {
    process: Process;
    process_started := false;
    is_attached := false;
    autostep := false;
    currently_updating_breakpoints := false;
    current_session_config_id: Remedy.rdbg_Id;
    stepped_on_frame: int;

    started_target_program_at: Time;
    last_focus_request_time: Time;
    WINDOW_FOCUS_REQUEST_INTERVAL :: 0.1;
    WINDOW_FOCUS_REQUEST_DURATION :: 1.0;

    current_buffer_id: int;
    current_line_number: int;

    breakpoints: [..] Breakpoint;

    state : enum {
        DORMANT :: 0;
        RUNNING;
        SUSPENDED;
    }

    icons :: struct {
        bug :: "\U0000f188";
        play :: "\U0000f04b";
        pause :: "\U0000f04c";
        step :: "\U0000f051";
        breakpoint :: "\U0001f518";  // circle="\U0001f7e4";
        blank :: " ";
    }
}

Breakpoint :: struct {
    uid: u32;
    buffer_id: int;
    line_number: int;
}


init_debugger :: () {
    Remedy.event_handles.exit_process = handle_exit_process_event;
    Remedy.event_handles.source_location_changed = handle_source_location_changed_event;
    Remedy.event_handles.target_continued = handle_target_continued_event;
    Remedy.event_handles.breakpoint_added = handle_breakpoint_added_event;
    Remedy.event_handles.breakpoint_resolved = handle_breakpoint_resolved_event;
    Remedy.event_handles.breakpoint_removed = handle_breakpoint_removed_event;
}

debugger_draw_ui :: () {
    if !debugger.state  return;

    h, s, l := hsl_from_rgb(Colors.UI_DEFAULT);
    h = fmod_cycling(cast(float)frame_time, 1.0);
    s = 1.0;
    color := rgb_from_hsl(h, s, l);
    color.a = 1;

    r := screen;
    r.w = dpi_scale;
    draw_rect(r, color);
    r.x += screen.w - dpi_scale;
    draw_rect(r, color);
    r = screen;
    r.h = dpi_scale;
    draw_rect(r, color);
    r.y += screen.h - dpi_scale;
    draw_rect(r, color);
}

update_attached_debugger :: () {
    if !debugger.is_attached  return;

    if frame_time < debugger.started_target_program_at + debugger.WINDOW_FOCUS_REQUEST_DURATION {
        if frame_time > debugger.last_focus_request_time + debugger.WINDOW_FOCUS_REQUEST_INTERVAL  {
            debugger.last_focus_request_time = frame_time;
            focus_focus();
        }
    }

    something_happened, error := Remedy.update();
    if error {
        error_msg := tprint("Got an error while updating the attached debugger: %\n", error);
        add_user_message_error(error_msg, duration_in_seconds=10, icon=debugger.icons.bug);
        log_error(error_msg);

        stop_debugger();
        debugger.is_attached = false;
        return;
    }

    if debugger.state == .DORMANT  return;

    if debugger.state == .SUSPENDED && debugger.autostep {
        debugger_step_over();
    }

    editting_locked_this_frame = true;

    editor, buffer := get_active_editor_and_buffer();
    if !editor return;

    add_status_part(editor, .icon, debugger.icons.bug, .{r=0, g=1, b=0, a=1});
    add_status_part(editor, .margin);
    if debugger.state == {
        case .RUNNING;
        h, s, l := hsl_from_rgb(Colors.UI_DEFAULT);
        h = fmod_cycling(cast(float)frame_time, 1.0);
        s = 1.0;
        color := rgb_from_hsl(h, s, l);
        add_status_part(editor, .icon, debugger.icons.play, color);

        case .SUSPENDED;
        animation_frame_duration :: 10;
        icon := ifx debugger.stepped_on_frame + animation_frame_duration >= frame_count
                then debugger.icons.step
                else debugger.icons.pause;
        add_status_part(editor, .icon, icon);
    }
    add_status_part(editor, .divider);
}

run_debugger :: () {
    if debugger.state == .RUNNING  return;

    // @TODO check debug target exists and dont run if it doesnt
    if !debugger.is_attached {
        success := attach_remedy();
        if !success  return;
    }

    if debugger.state == .DORMANT {
        result := Remedy.start_debugging(break_at_entry_point=false);
        if result.result == .OK {
            debugger.started_target_program_at = frame_time;
            set_debugger_state(.RUNNING);
        }
    }
    else {
        result := Remedy.continue_execution();
        if result.result == .OK
            set_debugger_state(.RUNNING);
    }
}

run_debugger_to_location :: (filename: string, line_number: int) {
    if debugger.state == .RUNNING  return;

    // @TODO check debug target exists and dont run if it doesnt
    if !debugger.is_attached {
        success := attach_remedy();
        if !success  return;
    }

    result := Remedy.run_to_file_at_line(filename, line_number + 1);
}

stop_debugger :: () {
    Remedy.stop_debugging();
    debugger.autostep = false;
    if active_global_widget == .debugger
        active_global_widget = .editors;
}

detach_debugger :: () {
    if debugger.is_attached      stop_debugger();
    if debugger.process_started  deinit(*debugger.process);
    debugger.is_attached = false;
}

debugger_run_to_cursor :: (editor: *Editor, using buffer: *Buffer) {
    cursor := leave_only_original_cursor(editor);
    coords := get_cursor_coords(editor, buffer, cursor);
    run_debugger_to_location(buffer.file.full_path, coords.pos.line);
}

debugger_handle_event :: (event: Input.Event) -> handled: bool {
    /*
    using icon_search_dialog;

    if event.type == .KEYBOARD && event.key_pressed {
        action, mapping := map_event_to_action(event, Action_Open_File_Dialog);
        if action == {
            case .close_dialog;             hide_icon_search_dialog();     return true;
            //case .open_entry_in_place;      open_selected_project();        return true;
            //case .open_entry_on_the_side;   open_selected_project();        return true;

            case .move_up;                  move_cursor(-1, wrap = true);   return true;
            case .move_down;                move_cursor( 1, wrap = true);   return true;
            case .move_up_fast;             move_cursor(-5);                return true;
            case .move_down_fast;           move_cursor( 5);                return true;
            case .move_up_one_page;         move_cursor(-per_page);         return true;
            case .move_down_one_page;       move_cursor( per_page);         return true;
        }

        handled := maybe_handle_text_input_event(*input, event);
        return handled;

    } else if event.type == .TEXT_INPUT {
        char := event.utf32;
        if char == 127 return true;  // there seems to be a bug in the Input module
                                // which generates a TEXT_INPUT event for DEL
                                // when Ctrl+Backspace is pressed

        text_input_type_char(*icon_search_dialog.input, char);
        refresh_entries();
        return true;
    }
    */
    return true;
}


debugger_toggle_breakpoint :: (editor: *Editor, using buffer: *Buffer) {
    for * cursor: editor.cursors {
        removed_it := false;
        coords := get_cursor_coords(editor, buffer, cursor);
        for debugger.breakpoints {
            if it.buffer_id == buffer.id && it.line_number == coords.pos.line {
                if debugger.state
                    Remedy.delete_breakpoint(it.uid);
                else
                    remove it;
                removed_it = true;
                break;
            }
        }
        if !removed_it {
            if debugger.state
                Remedy.add_breakpoint_at_filename_line(buffer.file.full_path, cast,trunc(u32) coords.pos.line + 1);
            else
                array_add(*debugger.breakpoints, Breakpoint.{ cast(u32) it_index, buffer.id, coords.pos.line });
        }
    }
}

debugger_remove_all_breakpoints :: () {
    if debugger.state
        Remedy.delete_all_breakpoints();

    array_reset(*debugger.breakpoints);
}

attach_remedy :: () -> success: bool {
    if debugger.is_attached  return true;

    debugger.autostep = false;

    if !debugger.is_attached {
        debugger.is_attached = Remedy.init();
        if debugger.is_attached  return true;
    }

    // Failed to attach pipes: probably remedy hasn't been started.

    success := create_process(*debugger.process, config.settings.remedy_executable_path, "--servername", Remedy.REMEDY_SERVERNAME, no_activate=true);
    if !success  return false;

    debugger.process_started = true;
    debugger.is_attached = Remedy.init();
    attempts := 5;
    while !debugger.is_attached && attempts {
        sleep_milliseconds(200);
        debugger.is_attached = Remedy.init();
        attempts -= 1;
    }

    if !debugger.is_attached  return false;


    check :: (result: *$T/Remedy.Result) -> *T #expand {
        if result.result != .OK {
            stop_debugger();
            debugger.is_attached = false;
            `return false;
        }
        return result;
    }

    check(Remedy.set_bring_to_foreground_on_suspended(false));
    check(Remedy.new_session());
    add_session_result := check(Remedy.add_session_config(command=config.settings.debug_target_path, working_dir=get_parent_dir_path(config.settings.debug_target_path)));
    debugger.current_session_config_id = add_session_result.uid;
    check(Remedy.set_active_session_config(debugger.current_session_config_id));

    debugger.currently_updating_breakpoints = true;
    for debugger.breakpoints  check(Remedy.add_breakpoint_at_filename_line(open_buffers[it.buffer_id].file.full_path, cast(u32) it.line_number + 1));
    debugger.currently_updating_breakpoints = false;
    fetch_breakpoints();

    return debugger.is_attached;
}

debugger_break :: () {
    if !debugger.state  return;

    Remedy.break_execution();
}

debugger_step_over :: () {
    if !debugger.state  return;

    Remedy.step_over_by_line();
    debugger.stepped_on_frame = frame_count;
}

debugger_step_into :: () {
    if !debugger.state  return;

    Remedy.step_into_by_line();
    debugger.stepped_on_frame = frame_count;
}

debugger_step_out :: () {
    if !debugger.state  return;

    Remedy.step_out();
    debugger.stepped_on_frame = frame_count;
}

debugger_toggle_autostep :: () {
    if !debugger.is_attached  return;

    debugger.autostep = !debugger.autostep;
}

debugger_temporary_test :: () {
    fetch_breakpoints();
}


#scope_file



set_debugger_state :: (state: type_of(debugger.state)) {
    debugger.state = state;
}

fetch_breakpoints :: () {
    result := Remedy.get_breakpoints();

    array_reset(*debugger.breakpoints);

    for result.breakpoints {
        breakpoint := array_add(*debugger.breakpoints);
        breakpoint.uid = it.uid;
        breakpoint.buffer_id = find_or_create_buffer(it.filename);
        breakpoint.line_number = it.line_num - 1;
    }
}

jump_to_source_location :: (path: string, line: u32) {
    editors_open_file(path, .in_place);
    if editors.active < 0 || line == 0  return;

    editor := *open_editors[editors.active];
    buffer := *open_buffers[editor.buffer_id];

    cursor := leave_only_original_cursor(editor);
    position := coords_to_offset(editor, buffer, .{ cast(s32)line - 1, 0 });
    cursor.pos = position;
    cursor.sel = position;
    add_paste_animation(editor, get_selection(cursor));
    editor.cursor_moved = .jumped;
    editor.scroll_to_cursor = .yes;

    debugger.current_buffer_id = editor.buffer_id;
    debugger.current_line_number = line - 1;
}

handle_target_continued_event :: (target_continued_event: Remedy.Event_Target_Continued) {
    set_debugger_state(.RUNNING);
}

handle_source_location_changed_event :: (event: Remedy.Event_Source_Location_Changed) {
    if #complete event.reason == {
        case .UNSPECIFIED;

        case .BY_COMMAND_LINE;        // An open-file from the command-line updated the source location
        case .BY_DRIVER;              // A RDBG_COMMAND_GOTO_FILE_AT_LINE from a named-pipes driver updated the source location
        case .BREAKPOINT_SELECTED;    // A selection of a breakpoint in breakpoints pane updated the source location
        case .CURRENT_FRAME_CHANGED;  // The current stack frame was changed in the callstack pane and updated the source location
        case .ACTIVE_THREAD_CHANGED;  // The active thread was changed in the threads pane and updated the source location

        //
        // The process was suspended and updated the source location
        //
        case .BREAKPOINT_HIT;
        case .EXCEPTION_HIT;
        case .STEP_OVER;
        case .STEP_IN;
        case .STEP_OUT;
        case .NON_USER_BREAKPOINT;
        case .DEBUG_BREAK;
    }

    focus_focus();
    if event.filename  jump_to_source_location(event.filename, event.line_num);
    set_debugger_state(.SUSPENDED);
}

handle_exit_process_event :: (exit_process_event: Remedy.Event_Exit_Process) {
    set_debugger_state(.DORMANT);
}


handle_breakpoint_added_event :: (breakpoint_added_event: Remedy.Event_Breakpoint_Added) {
}

handle_breakpoint_resolved_event :: (breakpoint_resolved_event: Remedy.Event_Breakpoint_Resolved) {
    if debugger.currently_updating_breakpoints  return;

    result := Remedy.get_breakpoint_locations(breakpoint_resolved_event.bp_id);

    for * debugger.breakpoints {
        if it.uid == result.bp_id {
            if result.locations {
                it.buffer_id = find_or_create_buffer(result.locations[0].filename);
                it.line_number = result.locations[0].actual_line_num - 1;
            }
            else {
                it.buffer_id = -1;
                it.line_number = -1;
            }
            return;
        }
    }

    // Didn't find it, so add it.
    breakpoint := array_add(*debugger.breakpoints);
    breakpoint.uid = result.bp_id;
    if result.locations {
        breakpoint.buffer_id = find_or_create_buffer(result.locations[0].filename);
        breakpoint.line_number = result.locations[0].actual_line_num - 1;
    }
    else {
        breakpoint.buffer_id = -1;
        breakpoint.line_number = -1;
    }
}

handle_breakpoint_removed_event :: (breakpoint_removed_event: Remedy.Event_Breakpoint_Removed) {
    for * debugger.breakpoints {
        if it.uid == breakpoint_removed_event.bp_id {
            remove it;
            return;
        }
    }
}

user32 :: #system_library "user32";
SetForegroundWindow :: (hwnd: HWND) -> s32 #foreign user32;

focus_focus :: () {
    SetForegroundWindow(window);
}
