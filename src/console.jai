console_initialized := false;
console_manually_opened := false;
console_mutex : Mutex;

init_console :: () {
    init(*console_mutex);
    init_console_buffer();

    console_thread_group = .{};
    init(*console_thread_group, 1, group_proc = console_threadproc);
    console_thread_group.name = "Console";
    console_thread_group.logging = false;
    for * console_thread_group.worker_info { it.thread.starting_context.logger_data = context.logger_data; }

    start(*console_thread_group);
    console_initialized = true;
}

init_console_buffer :: () {
    console_buffer_id = find_or_create_an_empty_buffer();
    buffer := *open_buffers[console_buffer_id];
    buffer.flags |= .readonly | .ignore | .manual_coloring;
    buffer.file.name = "<console>";
    buffer.file.icon = .console;
    print_console_header(tprint("Focus % built on %", VERSION, RELEASE_DATE), false);
    editors.floating = -1;
}

print_to_console :: inline (output: string, remain_closed := false) {
    print_to_console(output, false, Language.Plain_Text, remain_closed = remain_closed);
}

print_to_console :: inline (output: string, lang: Language, is_error := false, remain_closed := false) {
    print_to_console(output, false, lang, is_error, remain_closed = remain_closed);
}

print_to_console :: inline (output: string, append_newline: bool, remain_closed := false) {
    print_to_console(output, true, Language.Plain_Text, remain_closed = remain_closed);
}

print_to_console :: (output: string, append_newline: bool, lang: Language, is_error := false, $do_lock := true, remain_closed := false) {
    #if do_lock {
        lock(*console_mutex);
        defer unlock(*console_mutex);
    }

    assert(console_buffer_id >= 0 && open_buffers.count > console_buffer_id, "console_buffer_id: %  buffer count: %", console_buffer_id, open_buffers.count);
    buffer := *open_buffers[console_buffer_id];
    start := cast(s32) buffer.bytes.count;

    s := ifx append_newline then tprint("%\n", output) else output;
    insert_string_raw(buffer, buffer.bytes.count, s, false);
    rescan_for_lines(buffer);
    recalculate_colors(buffer); // resizes color array
    highlight_console_output(buffer, start, cast(s32)buffer.bytes.count - start, lang, is_error);

    editor := editor_showing_console();
    if !editor {
        was_closed := editors.floating < 0;
        show_console(false);
        editor = *open_editors[editors.floating];
        if was_closed && remain_closed  hide_console();
    }
    cursor := leave_only_original_cursor(editor);
    cursor.pos = xx buffer.bytes.count;
    cursor.sel = cursor.pos;
    add_paste_animation(editor, get_selection(cursor));
    editor.cursor_moved = .unimportant;
    editor.scroll_to_cursor = .yes;
}

editor_showing_console :: () -> *Editor {
    if #complete editors.layout == {
        case .None;
            return null;

        case .Single;
        if open_editors[editors.active].buffer_id == console_buffer_id
            return *open_editors[editors.active];

        case .Double;
        if open_editors[editors.left].buffer_id == console_buffer_id
            return *open_editors[editors.left];
        if open_editors[editors.right].buffer_id == console_buffer_id
            return *open_editors[editors.right];
    }
    return null;
}

print_console_header :: (s: string, leading_newline := true, is_error := false, remain_closed := false) -> Offset_Range, region_id: int {
    lock(*console_mutex);
    defer unlock(*console_mutex);

    assert(console_buffer_id >= 0 && open_buffers.count > console_buffer_id, "console_buffer_id: %  buffer count: %", console_buffer_id, open_buffers.count);
    buffer := *open_buffers[console_buffer_id];

    if leading_newline {
        if !ends_with_empty_line(buffer)
            print_to_console("\n", remain_closed=remain_closed);
     }
    start := cast(s32) buffer.bytes.count;
    print_to_console(s, true, .Plain_Text, false, remain_closed=remain_closed);
    end := cast(s32) buffer.bytes.count - 1;
    memset(buffer.colors.data + start, xx Code_Color.CONSOLE_HEADER_TEXT, end - start);
    id := add_buffer_region(buffer, start, end, true, 1, ifx is_error then .console_header_error else .console_header);
    return .{start, end}, id;
}

show_console :: (manually_opened: bool) {
    if manually_opened  console_manually_opened = true;
    editors_open_buffer(console_buffer_id, .floating);
}

hide_console :: () {
    console_manually_opened = false;
    editors.floating = -1;
}

toggle_console :: () {
    if editors.floating >= 0  hide_console();
    else                      show_console(true);
}

toggle_console_maximize :: () {
    if floating_area_position & .tall && !(floating_area_position & .narrow) {
        floating_area_position = set_bits(floating_area_position, floating_area_position_to_restore, .tall | .narrow);
    }
    else {
        floating_area_position_to_restore = set_bits(floating_area_position_to_restore, floating_area_position, .tall | .narrow);
        floating_area_position = set_bits(floating_area_position, .tall, .tall | .narrow);
    }
}


set_build_task_name :: (s: string) -> success: bool {
    if build_task_running  return false;
    if next_build_task_name  free(next_build_task_name.data, console_allocator);
    next_build_task_name = copy_string(s, console_allocator);
    return true;
}

set_build_task_dir :: (s: string) -> success: bool {
    if build_task_running  return false;
    if next_build_task_dir  free(next_build_task_dir.data, console_allocator);
    next_build_task_dir = copy_string(s, console_allocator);
    return true;
}

add_build_task_command :: (s: string) -> success: bool {
    if build_task_running  return false;
    array_add(*next_build_task_commands, copy_string(s, console_allocator));
    return true;
}

build_task_running := false;
build_task_header: Offset_Range;
build_task_region_id: int;
silence_stdout := false;

build :: () {
    if build_task_running  return;

    if random_build_icon_set  build_icon_set = xx random_int(xx #run enum_highest_value(type_of(build_icon_set)) + 1);
    if #complete build_icon_set == {
        case .dumpster_fire; build_icons = dumpster_icons;
        case .hourglass;     build_icons = hourglass_icons;
        case .poop;          build_icons = poop_icons;
        case .scales;        build_icons = scales_icons;
    }

    save_all(null, null, false, false);

    task := New(Console_Task, allocator=console_allocator);
    if next_build_task_name
        task.title = next_build_task_name;
    else
        task.title = copy_string(current_project_name, console_allocator);

    add_work(*console_thread_group, task, task.title);
}

build_finished_callback :: (error: string) { }

console_threadproc :: (group: *Thread_Group, thread: *Thread, work: *void) -> Thread_Continue_Status {
    using task := cast(*Console_Task) work;

    console_was_open := editors.floating >= 0 && console_manually_opened;
    start_time := frame_time;

    clear_build_errors();

    store_next_build_error = task.title;
    build_task_running = true;
    silence_stdout = false;
    defer {
        build_task_running = false;
        reset_build();
    }
    remove_delayed_action(hide_console);

    build_text := tprint("[BUILD] %", task.title);
    build_task_header, build_task_region_id = print_console_header(build_text, remain_closed=!config.settings.show_console_on_build);
    add_user_message(build_text, duration_in_seconds = -1, icon = to_string(*convert_utf32_to_utf8(xx build_icons[0])), origin = .build);

    successful := true;
    output: string;
    error: string;

    working_directory := ifx next_build_task_dir
                         then next_build_task_dir
                         else ifx project_dirs.count
                              then project_dirs[0].path
                              else "";

    if working_directory {
        for command: next_build_task_commands {
            if output  free(output);
            if error  free(error);

            result, output=, error=, timed_out := run_command(
                .. break_command_into_strings(command),
                working_directory = working_directory,
                capture_and_return_output = true,
                output_callback = on_output,
                error_callback = on_error
            );

            if result.exit_code {
                successful = false;
                break;
            }
        }
    }

    defer { free(error); free(output); }

    if successful {
        duration : float64 : 5;
        #if HIDE_CONSOLE_ON_SUCCESS
            if !console_was_open  add_delayed_action(hide_console, duration);
        set_build_header(ifx build_errors then .warning else .success);
        print_to_console(tprint("Success: % seconds\n", frame_time - start_time), remain_closed=!config.settings.show_console_on_build);
    }
    else {
        set_build_header(.error);
        if build_errors {
            #if TOAST_BUILD_RESULT {
                build_error := build_errors[0];
                add_user_error(tprint("%\n% %,%\n%", task.title, build_error.path, build_error.coords.line+1, build_error.coords.col+1, build_error.message), origin=.build);
            }
        }
        else if contains(output, "LNK1104") {
            #if TOAST_BUILD_RESULT {
                _, message := split_into_two(output, "LNK1104: ");
                _, path := split_into_two(message, "'");
                path, _ = split_into_two(path, "'");
                add_user_error(tprint("% - Linker error - %", task.title, trim(message)), origin=.build);
            }
        }
    }

    return .CONTINUE;
}

on_output :: (s: string) {
    if !silence_stdout
        print_to_console(s, .Jai, remain_closed=!config.settings.show_console_on_build);
}

on_error :: (s: string) {
    is_first_error := build_errors.count == 0;
    print_to_console(s, .Jai, is_error = true, remain_closed=!config.settings.show_console_on_build);
    if build_errors && is_first_error {
        set_build_header(.error);
        #if BUILD_SILENCE_STDOUT_AFTER_ERROR
            silence_stdout = true;
        #if AUTO_JUMP_TO_ERROR  jump_to_error();
    }
}

set_build_header :: (result: User_Message.Level) {
    buffer := *open_buffers[console_buffer_id];
    region := get_buffer_region(buffer, build_task_region_id);
    if region {
        region.type = ifx result != .error
                      then .console_header_success
                      else .console_header_error;
    }
    set_user_build_message(result);
}

clear_build_errors :: () {
    if !build_errors  return;
    for * build_errors {
        if it.decorated_buffer_id >= 0 {
            buffer := *open_buffers[it.decorated_buffer_id];
            buffer.flags |= .needs_coloring;
        }
        free_build_error_members(it);
    }
    array_reset(*build_errors);
    last_jumped_to_build_error = -1;
}

add_build_error :: (location: string, coords: Coords, kind: type_of(Build_Error.kind), message: string) -> Build_Error {
    build_error := make_build_error(location, coords, kind, trim(message));
    decorate_with_build_error(*build_error);
    array_add(*build_errors, build_error);
    return build_error;
}

make_build_error :: (location: string, coords: Coords, kind: type_of(Build_Error.kind), _message: string) -> Build_Error {
    result : Build_Error = ---;

    result.path = copy_string(platform_normalize_path(location), console_allocator);
    result.coords = coords;
    if result.coords.col < 0  result.coords.col = 0;
    result.kind = kind;
    result.decorated_buffer_id = -1;

    //message_char_width := window_width / 2 / font_ui.x_advance;
    message_char_width :: 40;
    message := _message;
    if message.count > message_char_width {
        builder : String_Builder;
        part: string;
        while message {
            i := last_index(message, #char " ", message_char_width);
            if i <= 0  i = message_char_width;
            part, message = split_at_index(message, i);
            append(*builder, part);
            append(*builder, #char "\n");
            message = trim_start(message);
            if message.count <= message_char_width {
                append(*builder, message);
                append(*builder, #char "\n");
                break;
            }
        }
        message = builder_to_string(*builder, temp);
    }
    result.message = copy_string(trim_end(message), console_allocator);

    return result;
}

free_build_error_members :: (build_error: *Build_Error) {
    if build_error.path     free(build_error.path.data, console_allocator);
    if build_error.message  free(build_error.message.data, console_allocator);
}

decorate_with_build_error :: (build_error: *Build_Error ) {
    buffer_index := find_or_create_buffer(build_error.path);
    if buffer_index < 0  return;

    buffer := *open_buffers[buffer_index];
    build_error.decorated_buffer_id = buffer_index;
    buffer.flags |= .needs_coloring;
}


build_errors : [..] Build_Error;
last_jumped_to_build_error := -1;
store_next_build_error := "";


Build_Error :: struct {
    path : string;
    coords : Coords;
    message : string;
    decorated_buffer_id := -1;
    kind : enum {
        info;
        warning;
        error;
    }
}

reset_build :: () {
    if next_build_task_name  free(next_build_task_name.data, console_allocator);
    next_build_task_name = "";
    if next_build_task_dir  free(next_build_task_dir.data, console_allocator);
    next_build_task_dir = "";
    for next_build_task_commands  free(it.data, console_allocator);
    array_reset(*next_build_task_commands);
}

console_allocator : Allocator;
console_thread_group : Thread_Group;

random_build_icon_set := true;
build_icon_set : enum {
    dumpster_fire;
    hourglass;
    poop;
    scales;
} = .dumpster_fire;

dumpster_icons  :: All_Icons.[ .dumpster, .dumpster, .dumpster_fire, ];
hourglass_icons :: All_Icons.[ .hourglass_start, .hourglass_half, .hourglass_end, .hourglass_end ];
poop_icons      :: All_Icons.[ .poop, .poop, .poo ];
scales_icons    :: All_Icons.[ .scale_balanced, .scale_unbalanced, .scale_balanced, .scale_unbalanced_flip ];

build_icons : [] All_Icons;

console_buffer_id : s64 = -1;

#scope_file

next_build_task_name := "";
next_build_task_dir := "";
next_build_task_commands : [..] string;

Console_Task :: struct {
    title : string;
}

Color :: enum {
    plain;
    location;
    error;
    info;
}

// Must match the order of the types in the enum
COLOR_MAP :: Code_Color.[
    .CONSOLE_TEXT,   // plain
    .STRING,         // location
    .CONSOLE_ERROR,  // error
    .VALUE,          // header
];

// @Note Unlike other highlight_ procedures, the console highlight procedure only gets called once when data
//       is written to the console buffer.  It is not called every frame.   Therefor, it does not necessarily
//       have to be as performant, and we can do work in it (such as error parsing)

highlight_console_output :: (buffer: *Buffer, start_index: s32, count: s32, lang: Language, is_error: bool) {
    if lang == {
        case .Jai;
        highlight_console_jai_output(buffer, start_index, count, is_error);

        case .Focus_Config;
        highlight_console_focus_config(buffer, start_index, count);
    }
}

highlight_console_focus_config :: (buffer: *Buffer, start_index: s32, count: s32) {
    highlight_focus_config_syntax(buffer, start_index, count);
    add_buffer_region(buffer, start_index, start_index + count, false, 1, .todo_definitely_todo_this);
}

highlight_console_jai_output :: (buffer: *Buffer, start_index: s32, count: s32, is_error: bool) {
    code_start: *u8;
    in_code_block := false;

    first_u8_byte := buffer.bytes.data + start_index;
    first_color_byte := buffer.colors.data + start_index;

    s : string = ---;
    s.data = first_u8_byte;
    s.count = count;

    highlight_last_caret :: (start: s32, end: s32) #expand {
        assert(end > start);
        s : string = ---;
        s.data = `buffer.bytes.data + start;
        s.count = end - start;
        i, found := last_index(s, #char "^");
        while found {
            `buffer.colors[start + i] = xx COLOR_MAP[Color.error];
            i -= 1;
            found = i >= 0 && `buffer.bytes[start + i] == #char "^";
        }
    }

    look_for_special_case := false;

    for line: line_split(s) {
        if !line {
            if !code_start
                code_start = line.data;
            continue;
        }

        if line[0] <= #char " " {
            if code_start
                in_code_block = true;
            continue;
        }

        if in_code_block {
            in_code_block = false;
            start := cast(s32)(code_start - buffer.bytes.data);
            end := cast(s32)(line.data - buffer.bytes.data - 1);
            highlight_jai_syntax(buffer, start, end - start);
            add_buffer_region(buffer, start, end, false, 1, .todo_definitely_todo_this);
            highlight_last_caret(start, end);
            code_start = null;
        }

        if !is_error || line.count < 10  continue;

        replaced_early_colon := false;
        if line[1] == #char ":" {
            line[1] = #char " ";
            replaced_early_colon = true;
        }

        parts : [4] string;
        split(*parts, line, #char ":");
        if parts[3] {
            if replaced_early_colon  line[1] = #char ":";
            coords, is_location_message := coords_from_string(parts[1]);
            if is_location_message {
                location := parts[0];
                location.count += 1 + parts[1].count;
                kind_string := parts[2];
                set_color(location, .location);
                error_kind : type_of(Build_Error.kind) = .info;
                color := Color.info;
                if kind_string == {
                    case " Error";
                    error_kind = .error;
                    color = Color.error;

                    case " Warning"; // does this exist?
                    error_kind = .warning;

                    case " Info";
                }
                set_color(kind_string, color);

                build_error := add_build_error(parts[0], coords, error_kind, parts[3]);
                target_buffer_index := find_buffer(build_error.path);
                if target_buffer_index >= 0
                    add_source_location_decoration(buffer, xx (parts[2].data - buffer.bytes.data), xx target_buffer_index, real_coords_to_offset(open_buffers[target_buffer_index], build_error.coords));
            }
        }
        else {
            if replaced_early_colon  line[1] = #char ":";
        }
    }

    if in_code_block {
        start := cast(s32)(code_start - buffer.bytes.data);
        end := cast(s32)(start_index + count - 1);
        highlight_jai_syntax(buffer, start, end - start);
        add_buffer_region(buffer, start, end, false, 1, .todo_definitely_todo_this);
        highlight_last_caret(start, end);
    }
}


set_color :: (s: string, color: Color) #expand {
    offset := s.data - `first_u8_byte;
    memset(`first_color_byte + offset, xx COLOR_MAP[color], s.count);
}