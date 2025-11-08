// TODO
// [ ] Add key layer for debug commands

debugger: struct {
    process: Process;
    process_started := false;
    is_attached := false;
    target_pdb_path: string;
    last_file_save_at: Apollo_Time;
    last_build_at: Apollo_Time;
    last_jump_to_source_location_invalid := false;

    waiting_to_run := 0;
    waiting_to_run_attempts := 0;
    waiting_to_run_filename: string;
    waiting_to_run_line_number: int;

    max_step_outs_before_giving_up :: 100;
    advance_to_next_valid_location_attempts := 0;
    disable_advance_to_next_valid_location := false;

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
    breakpoints_enabled := true;

    watch_allocator: Allocator;
    watch_allocator_pool: Flat_Pool;
    watch_cache: Table(string, Watch_Entry);

    word_at_cursor: string;
    word_at_cursor_pos: s32;

    state : enum {
        DORMANT :: 0;
        RUNNING;
        SUSPENDED;
    }

    icons :: struct {
        bug :: "\U0000f188";
        build_out_of_date :: "\U0000e4eb";
        play :: "\U0000f04b";
        pause :: "\U0000f04c";
        step :: "\U0000f051";
        breakpoint :: "\U0001f518";  // circle="\U0001f7e4";
        disabled_breakpoint :: "\U0000006f";
        cursor_suspended :: "\U0000f28c";
        cursor_running :: "\U0000f144";
        cursor_background :: "\U0001f7e4";
        circle :: "\U0001f7e4";
        blank :: " ";
    }

    // Remedy only knows the paths to files from the PDB, but files may be accessed via different path strings
    // (e.g. case, symlinks).  Hopefully in future Remedy will check the canonical paths of files to deduplicate
    // them, but until then we keep track of the filenames which are used to create buffers in this table.
    // If we step into a file via remedy then it will give us the filename it expects, so we will work for those
    // cases if we use this lookup. We're still potentially screwed if the user has opened the file via the open
    // file dialog...  This table goes away if Remedy gets patched.
    remedy_filenames: Table(string, string);
}

Breakpoint :: struct {
    uid: u32;
    pos: s32;
    buffer_id: int;
    line_number: int;
}

Watch_Entry :: struct  {
    value_buffer: u64;
    value: Any;
}


init_debugger :: () {
    debugger.watch_allocator.proc = flat_pool_allocator_proc;
    debugger.watch_allocator.data = *debugger.watch_allocator_pool;
    init(*debugger.watch_cache,, debugger.watch_allocator);

    Remedy.event_handles.exit_process = handle_exit_process_event;
    Remedy.event_handles.source_location_changed = handle_source_location_changed_event;
    Remedy.event_handles.target_continued = handle_target_continued_event;
    Remedy.event_handles.breakpoint_added = handle_breakpoint_added_event;
    Remedy.event_handles.breakpoint_resolved = handle_breakpoint_resolved_event;
    Remedy.event_handles.breakpoint_removed = handle_breakpoint_removed_event;
}

refresh_from_config_debugger_info :: () {
    if !config.settings.debug_target_path  return;

    path, basename, extension, basename_with_extension := path_decomp(config.settings.debug_target_path);
    if debugger.target_pdb_path  free(debugger.target_pdb_path);
    debugger.target_pdb_path = join(path, basename, ".pdb");
} @OnConfigRefresh

attach_remedy :: () -> success: bool {
    if debugger.is_attached  return true;

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
    add_session_result := check(Remedy.add_session_config(
                                        command=config.settings.debug_target_path,
                                        working_dir=get_parent_dir_path(config.settings.debug_target_path),
                                        name="Locus attached session"));
    debugger.current_session_config_id = add_session_result.uid;
    check(Remedy.set_active_session_config(debugger.current_session_config_id));

    debugger.currently_updating_breakpoints = true;
    for * breakpoint: debugger.breakpoints {
        add_breakpoint_result := check(Remedy.add_breakpoint_at_filename_line(get_remedy_filename(open_buffers[breakpoint.buffer_id].file.full_path), cast(u32) breakpoint.line_number + 1));
        breakpoint.uid = add_breakpoint_result.bp_id;
        if !debugger.breakpoints_enabled  check(Remedy.enable_breakpoint(breakpoint.uid, debugger.breakpoints_enabled));
    }
    debugger.currently_updating_breakpoints = false;

    return debugger.is_attached;
}

update_attached_debugger :: () {
    if !debugger.is_attached  return;

    if frame_time < debugger.started_target_program_at + debugger.WINDOW_FOCUS_REQUEST_DURATION {
        if frame_time > debugger.last_focus_request_time + debugger.WINDOW_FOCUS_REQUEST_INTERVAL  {
            debugger.last_focus_request_time = frame_time;
            if config.settings.focus_focus_on_debug
                focus_focus();
        }
    }

    something_happened, error := Remedy.update();
    if error {
        error_msg := tprint("Got an error while updating the attached debugger: %\n", error);
        add_user_message_error(error_msg, duration_in_seconds=10, icon=debugger.icons.bug);

        stop_debugger();
        debugger.is_attached = false;
        return;
    }

    if debugger.state  editting_locked_this_frame = true;

    if debugger.state == .SUSPENDED {
        if debugger.autostep {
            debugger_step_over();
        }
        else if debugger.last_jump_to_source_location_invalid && !debugger.disable_advance_to_next_valid_location {
            debugger.advance_to_next_valid_location_attempts -= 1;
            if debugger.advance_to_next_valid_location_attempts == 0
                debugger.disable_advance_to_next_valid_location = true;
            else
                debugger_step_out();
        }
    }

    editor, buffer := get_active_editor_and_buffer();
    if !editor return;

    cursor := *editor.cursors[editor.main_cursor];
    debugger.word_at_cursor = "";
    start_pos, end_pos := bracket_word_at_cursor(buffer, cursor);
    if start_pos >= 0 && start_pos < buffer.bytes.count && end_pos > start_pos {
        word : string = ---;
        word.data = buffer.bytes.data + start_pos;
        word.count = end_pos - start_pos;
        if get_char_type(word[0]) == .word {
            debugger.word_at_cursor = word;
            debugger.word_at_cursor_pos = start_pos;
        }
    }

    color := debugger_color_for_state(Colors.UI_DEFAULT);

    if #complete debugger.state == {
        case .DORMANT;
        if debugger.last_file_save_at > debugger.last_build_at {
            add_status_part(editor, .icon, debugger.icons.bug);
            add_status_part(editor, .margin);
            add_status_part(editor, .icon, debugger.icons.build_out_of_date);
            add_status_part(editor, .divider);
        }
        else if !config.settings.hide_debugger_attached_icon {
            add_status_part(editor, .icon, debugger.icons.bug);
            add_status_part(editor, .divider);
        }

        case .RUNNING;
        add_status_part(editor, .icon, debugger.icons.bug, .{r=0, g=1, b=0, a=1});
        add_status_part(editor, .margin);
        add_status_part(editor, .icon, debugger.icons.play, color);
        add_status_part(editor, .divider);

        case .SUSPENDED;
        animation_frame_duration :: 10;
        icon := ifx debugger.stepped_on_frame + animation_frame_duration >= frame_count
                then debugger.icons.step
                else debugger.icons.pause;
        add_status_part(editor, .icon, debugger.icons.bug, color);
        add_status_part(editor, .margin);
        add_status_part(editor, .icon, icon);
        add_status_part(editor, .divider);
    }

}

debugger_color_for_state :: (dormant_color: Color) -> Color {
    if #complete debugger.state == {
        case .DORMANT;
            return dormant_color;

        case .SUSPENDED;
            return Colors.DEBUGGER_NEXT_INSTRUCTION;

        case .RUNNING;
            return frame_hsl_color();
    }
}

debugger_draw_ui :: () {
    if !debugger.state  return;

    color := debugger_color_for_state(Colors.UI_DEFAULT);

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

debugger_is_waiting_to_run :: () -> bool {
    return debugger.waiting_to_run > debugger.waiting_to_run_attempts;
}

debugger_request_delayed_run :: (filename := "", line_number := 0) {
    debugger.waiting_to_run += 1;
    debugger.waiting_to_run_filename = filename;
    debugger.waiting_to_run_line_number = line_number;
}

debugger_trigger_delayed_run :: () {
    if !debugger_is_waiting_to_run()  return;
    debugger.waiting_to_run_attempts += 1;
    if debugger.waiting_to_run_filename
        run_debugger_to_location(debugger.waiting_to_run_filename, debugger.waiting_to_run_line_number, from_delay=true);
    else
        run_debugger(from_delay=true);
}

debugger_cancel_delayed_run :: () {
    if debugger_is_waiting_to_run()
        debugger.waiting_to_run_attempts += 1;
}

#scope_file

reset_for_new_run :: () {
    debugger.autostep = false;
    debugger.disable_advance_to_next_valid_location = false;
    debugger.last_jump_to_source_location_invalid = false;
    debugger.word_at_cursor = "";
    reset(*debugger.watch_allocator_pool);
    table_reset(*debugger.watch_cache);
}

check_debug_target :: (from_delay := true) -> path_ok: bool {
    check :: (condition: bool, message: string, duration_in_seconds := 10, build_if_unsuccessful := true) #expand {
        if !condition {
            if build_if_unsuccessful && config.settings.build_on_debug_if_needed && !debugger_is_waiting_to_run() && !from_delay {
                ficus_execute_string(config.settings.build_on_debug_if_needed, .user, .default);
                debugger_request_delayed_run();
            }
            else {
                add_user_message_error(message, duration_in_seconds=duration_in_seconds, icon=debugger.icons.bug);
            }
            `return false;
        }
    }

    check(config.settings.debug_target_path != "", "debug_target_path not set in any config file!\n", build_if_unsuccessful=false);
    check(file_exists(config.settings.debug_target_path), tprint("debug_target_path is: %, but that file does not exist.\n", config.settings.debug_target_path));
    check(file_exists(debugger.target_pdb_path), tprint("debugger.target_pdb_path is: %, but that file does not exist.\n", debugger.target_pdb_path));

    modtime, size, success := file_modtime_and_size(debugger.target_pdb_path);
    check(success, tprint("debugger.target_pdb_path is: %, but it could not be read.\n", debugger.target_pdb_path));

    debugger.last_build_at = modtime;
    build_time_ok := debugger.last_file_save_at <= debugger.last_build_at;
    check(build_time_ok, "Files have been saved since the debug target was last built: to debug it you must build it again.\n");

    return true;
}

#scope_export

run_debugger :: (from_delay := false) {
    if debugger.state == .RUNNING  return;

    if config.settings.save_on_debug  save_all(include_fileless_buffers=false);

    if !check_debug_target(from_delay)  return;

    if !debugger.is_attached {
        success := attach_remedy();
        if !success  return;
    }

    reset_for_new_run();

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

run_debugger_to_location :: (filename: string, line_number: int, from_delay := false) {
    if debugger.state == .RUNNING  return;

    if config.settings.save_on_debug  save_all(include_fileless_buffers=false);

    if !check_debug_target()  return;

    if !debugger.is_attached {
        success := attach_remedy();
        if !success  return;
    }

    reset_for_new_run();

    result := Remedy.run_to_file_at_line(get_remedy_filename(filename), cast,trunc(u32) line_number + 1);
}

stop_debugger :: () {
    if !check_debugger_command_is_valid()  return;

    Remedy.stop_debugging();
    debugger.state = .DORMANT;
    if active_global_widget == .debugger
        active_global_widget = .editors;
}

detach_debugger :: () {
    if !check_debugger_command_is_valid()  return;

    if debugger.is_attached      stop_debugger();
    if debugger.process_started  deinit(*debugger.process);
    debugger.is_attached = false;
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

debugger_run_to_cursor :: (editor: *Editor, using buffer: *Buffer) {
    cursor := leave_only_original_cursor(editor);
    coords := get_cursor_coords(editor, buffer, cursor);
    run_debugger_to_location(buffer.file.full_path, coords.pos.line);
}

debugger_toggle_breakpoint :: (editor: *Editor, using buffer: *Buffer) {
    if !check_debugger_command_is_valid()  return;

    for * cursor: editor.cursors {
        removed_it := false;
        pos := get_real_line_end_offset(buffer, offset_to_real_line(buffer, cursor.pos));
        coords := get_cursor_coords(editor, buffer, cursor);
        for debugger.breakpoints {
            if it.buffer_id == buffer.id && it.line_number == coords.pos.line {
                if debugger.is_attached
                    debugger_remove_breakpoint(it.uid);
                else
                    remove it;
                removed_it = true;
                break;
            }
        }
        if !removed_it {
            breakpoint := array_add(*debugger.breakpoints);
            if debugger.is_attached {
                result := Remedy.add_breakpoint_at_filename_line(get_remedy_filename(buffer.file.full_path), cast,trunc(u32) coords.pos.line + 1);
                breakpoint.* = .{ result.bp_id, pos, buffer.id, coords.pos.line };
            }
            else {
                breakpoint.* = .{ get_uid(), pos, buffer.id, coords.pos.line };
            }
        }
    }
}

debugger_toggle_all_breakpoints :: () {
    debugger.breakpoints_enabled = !debugger.breakpoints_enabled;
    if debugger.is_attached {
        for * breakpoint: debugger.breakpoints
            Remedy.enable_breakpoint(breakpoint.uid, debugger.breakpoints_enabled);
    }
}

debugger_update_breakpoint_line :: (uid: u32, line_number: int) {
    if debugger.is_attached {
        Remedy.update_breakpoint_line(uid, cast,trunc(u32) line_number + 1);
    }
    else {
        for * breakpoint: debugger.breakpoints {
            if breakpoint.uid == uid {
                breakpoint.line_number = line_number;
                return;
            }
        }
    }
}

debugger_remove_breakpoint :: (uid: u32) {
    if debugger.is_attached {
        Remedy.delete_breakpoint(uid);
    }
    else {
        for * breakpoint: debugger.breakpoints {
            if breakpoint.uid == uid {
                remove breakpoint;
                return;
            }
        }
    }
}

debugger_remove_all_breakpoints :: () {
    if !check_debugger_command_is_valid()  return;

    if debugger.is_attached
        Remedy.delete_all_breakpoints();

    array_reset(*debugger.breakpoints);
}

debugger_break :: () {
    if !check_debugger_command_is_valid()  return;

    if !debugger.state  return;

    Remedy.break_execution();
}

debugger_step_over :: () {
    if !check_debugger_command_is_valid()  return;

    if !debugger.state  return;

    Remedy.step_over_by_line();
    debugger.stepped_on_frame = frame_count;
}

debugger_step_into :: () {
    if !check_debugger_command_is_valid()  return;

    if !debugger.state  return;

    Remedy.step_into_by_line();
    debugger.stepped_on_frame = frame_count;
}

debugger_step_out :: () {
    if !check_debugger_command_is_valid()  return;

    if !debugger.state  return;

    Remedy.step_out();
    debugger.stepped_on_frame = frame_count;
}

debugger_toggle_autostep :: () {
    if !check_debugger_command_is_valid()  return;

    if !debugger.is_attached  return;

    debugger.autostep = !debugger.autostep;
}

debugger_temporary_test :: () {
    add_user_message("Doing something!");

    //fetch_breakpoints();
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
        breakpoint.pos = get_real_line_end_offset(*open_buffers[breakpoint.buffer_id], cast,trunc(s32) breakpoint.line_number);;
    }
}

jump_to_source_location :: (path: string, line: u32) {
    debugger.last_jump_to_source_location_invalid = false;
    editors_open_file(path, .in_place);
    if editors.active < 0 || line == 0 {
        debugger.last_jump_to_source_location_invalid = true;
        return;
    }

    editor := *open_editors[editors.active];
    buffer := *open_buffers[editor.buffer_id];

    cursor := leave_only_original_cursor(editor);
    position := coords_to_offset(editor, buffer, .{ cast(s32)line - 1, cursor.col_wanted });
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
    else               debugger.last_jump_to_source_location_invalid = true;

    if debugger.last_jump_to_source_location_invalid && debugger.advance_to_next_valid_location_attempts == 0 {
        debugger.advance_to_next_valid_location_attempts = debugger.max_step_outs_before_giving_up;
    }

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

    for * breakpoint: debugger.breakpoints {
        if breakpoint.uid == result.bp_id {
            if result.locations {
                breakpoint.buffer_id = find_or_create_buffer(result.locations[0].filename);
                breakpoint.line_number = result.locations[0].actual_line_num - 1;
                breakpoint.pos = get_real_line_end_offset(*open_buffers[breakpoint.buffer_id], cast,trunc(s32) breakpoint.line_number);;
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
        breakpoint.pos = get_real_line_end_offset(*open_buffers[breakpoint.buffer_id], cast,trunc(s32) breakpoint.line_number);;
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


next_uid: u32 = 0;
get_uid :: inline () -> u32 {
    next_uid -= 1;
    return next_uid;
}

get_remedy_filename :: (filename: string) -> string {
    canonical_path := get_canonical_path(filename);
    remedy_path, found := table_find(*debugger.remedy_filenames, canonical_path);
    if found  return remedy_path;
    else      return filename;
}

check_debugger_command_is_valid :: () -> bool {
    if !config.settings.debug_target_path {
        add_user_message_warning("To debug you must set debug_target_path in your config [[settings]].", duration_in_seconds=3, icon=debugger.icons.bug);
        return false;
    }

    return true;
}


#scope_module


Ball_Cursor :: struct {
    gravity :: 3000.0;
    normal_leap_duration :: 0.33;

    leap_duration: float;
    started_bounce_at: Time;
    next_bounce_at: Time;

    start_position: Vector2;
    end_position: Vector2;
    current_position: Vector2;
    velocity: Vector2;
}

ball_cursor: Ball_Cursor;

calculate_next_bounce :: (using ball: *Ball_Cursor, target_position: Vector2) {
    leap_duration = ifx frame_time < next_bounce_at // interrupted
                    then normal_leap_duration / 2
                    else normal_leap_duration;
    started_bounce_at = frame_time;
    next_bounce_at = frame_time + cast(Time)leap_duration;
    start_position = .{ current_position.x, end_position.y };
    end_position = target_position;

    delta := end_position - start_position;
    velocity.x = delta.x / leap_duration;
    velocity.y = (delta.y + 0.5 * gravity * leap_duration * leap_duration) / leap_duration;
}

get_ball_position :: (using ball: *Ball_Cursor, t: Time) -> Vector2 {
    time := cast(float)(frame_time - started_bounce_at);
    current_position = start_position + (velocity * time);
    current_position.y -= 0.5 * gravity * time * time;
    return current_position;
}