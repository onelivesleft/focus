console_initialized := false;
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

print_to_console :: inline (output: string) {
    print_to_console(output, false, Language.Plain_Text);
}

print_to_console :: inline (output: string, lang: Language) {
    print_to_console(output, false, lang);
}

print_to_console :: inline (output: string, append_newline: bool) {
    print_to_console(output, true, Language.Plain_Text);
}

print_to_console :: (output: string, append_newline: bool, lang: Language, $do_lock := true) {
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
    highlight_console_output(buffer, start, cast(s32)buffer.bytes.count - start, lang);

    editors_open_buffer(console_buffer_id, .floating);
    editor := *open_editors[editors.floating];
    cursor := leave_only_original_cursor(editor);
    cursor.pos = xx buffer.bytes.count;
    cursor.sel = cursor.pos;
    add_paste_animation(editor, get_selection(cursor));
    editor.cursor_moved = .unimportant;
    editor.scroll_to_cursor = .yes;
}

print_console_header :: (s: string, leading_newline := true, is_error := false) -> Offset_Range, region_id: int {
    lock(*console_mutex);
    defer unlock(*console_mutex);

    assert(console_buffer_id >= 0 && open_buffers.count > console_buffer_id, "console_buffer_id: %  buffer count: %", console_buffer_id, open_buffers.count);
    buffer := *open_buffers[console_buffer_id];

    if leading_newline  print_to_console("\n");
    start := cast(s32) buffer.bytes.count;
    print_to_console(s, true, .Plain_Text, false);
    end := cast(s32) buffer.bytes.count - 1;
    memset(buffer.colors.data + start, xx Code_Color.CONSOLE_HEADER_TEXT, end - start);
    id := add_buffer_region(buffer, start, end, true, 1, ifx is_error then .console_header_error else .console_header);
    return .{start, end}, id;
}

clear_console :: (header := "") {
    assert(console_buffer_id >= 0 && open_buffers.count > console_buffer_id, "console_buffer_id: %  buffer count: %", console_buffer_id, open_buffers.count);
    buffer := *open_buffers[console_buffer_id];
    clear_buffer(buffer);
    if header  insert_string_raw(buffer, buffer.bytes.count, header, false);
    rescan_for_lines(buffer);
    editors_open_buffer(console_buffer_id, .floating);
}

show_console :: () {
    editors_open_buffer(console_buffer_id, .floating);
}

hide_console :: () {
    editors.floating = -1;
}

toggle_console :: () {
    if editors.floating >= 0  hide_console();
    else                      show_console();
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

build :: () {
    if build_task_running  return;

    if random_build_icon_set  build_icon_set = xx random_int(xx #run enum_highest_value(type_of(build_icon_set)) + 1);
    if #complete build_icon_set == {
        case .dumpster_fire; build_icons = dumpster_icons;
        case .hourglass;     build_icons = hourglass_icons;
        case .poop;          build_icons = poop_icons;
        case .scales;        build_icons = scales_icons;
    }

    clear_user_messages(.build);

    save_all(null, null, false);

    task := New(Console_Task, allocator=console_allocator);
    if next_build_task_name
        task.title = next_build_task_name;
    else
        task.title = copy_string(current_project_name, console_allocator);

    add_work(*console_thread_group, task, task.title);
}

console_threadproc :: (group: *Thread_Group, thread: *Thread, work: *void) -> Thread_Continue_Status {
    using task := cast(*Console_Task) work;

    console_was_open := editors.floating >= 0;
    start_time := frame_time;

    if build_error_exists {
        if last_build_error.decorated_buffer
            last_build_error.decorated_buffer.flags |= .needs_coloring;
        build_error_exists = false;
    }
    store_next_build_error = task.title;
    build_task_running = true;
    defer {
        build_task_running = false;
        reset_build();
    }
    remove_delayed_action(hide_console);

    build_task_header, build_task_region_id = print_console_header(tprint("[BUILD] %", task.title));

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
                output_callback = print_to_console,
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
        add_success_message(tprint("% Success!", task.title), origin=.build, dismiss_in_seconds = duration);
        #if HIDE_CONSOLE_ON_SUCCESS  if !console_was_open add_delayed_action(hide_console, duration);
        set_build_header(success=true);
        print_to_console(tprint("Success: % seconds\n", frame_time - start_time));
    }
    else {
        if build_error_exists {
            //add_user_error(tprint("%\n% %,%\n%", task.title, last_build_error.path, last_build_error.coords.line+1, last_build_error.coords.col+1, last_build_error.message), last_build_error.path, origin=.build);
            //#if AUTO_JUMP_TO_ERROR  jump_to_error();
        }
        else if contains(output, "LNK1104") {
            _, message := split_into_two(output, "LNK1104: ");
            _, path := split_into_two(message, "'");
            path, _ = split_into_two(path, "'");
            add_user_error(tprint("%\nLinker error\n%", task.title, trim(message)), path, origin=.build);
        }
    }

    return .CONTINUE;
}

on_error :: (s: string) {
    print_to_console(s, .Jai);
    if store_next_build_error {
        build_error, ok := make_build_error(s);
        if ok {
            free_build_error_members(*last_build_error);
            last_build_error = build_error;
            build_error_exists = true;
            decorate_last_build_error();
            add_user_error(tprint("%\n% %,%\n%", store_next_build_error, last_build_error.path, last_build_error.coords.line+1, last_build_error.coords.col+1, last_build_error.message), last_build_error.path, origin=.build);
            set_build_header(success=false);
            store_next_build_error = "";
            #if AUTO_JUMP_TO_ERROR  jump_to_error();
        }
    }
}

set_build_header :: (success: bool) {
    buffer := *open_buffers[console_buffer_id];
    region := get_buffer_region(buffer, build_task_region_id);
    if region {
        region.type = ifx success then .console_header_success
                                  else .console_header_error;
    }
}

make_build_error :: (s: string) -> Build_Error, ok: bool {
    result : Build_Error = ---;
    sentinel :: ": Error: ";
    if !contains(s, sentinel) return result, false;

    line := trim(s);

    location, message := split_into_two(line, sentinel);
    location = slice(location, last_index(location, #char "\n") + 1);

    coord_start := last_index(location, #char ":");
    coords := slice(location, coord_start + 1);
    ok : bool;
    result.coords, ok = coords_from_string(coords);
    if !ok  return result, false;

    result.path = copy_string(platform_normalize_path(slice(location, 0, coord_start)), console_allocator);
    message = split_into_two(message, #char "\n");
    message_char_width :: 96;
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
    result.decorated_buffer = null;

    return result, true;
}

free_build_error_members :: (build_error: *Build_Error) {
    if build_error.path     free(build_error.path.data, console_allocator);
    if build_error.message  free(build_error.message.data, console_allocator);
}

decorate_last_build_error :: (buffer: *Buffer = null) {
    if !build_error_exists  return;

    if buffer {
        if !platform_path_equals(buffer.file.full_path, last_build_error.path)
            return;
    }
    else {
        buffer_index := find_buffer(last_build_error.path);
        if buffer_index < 0  return;

        buffer = *open_buffers[buffer_index];
    }

    last_build_error.decorated_buffer = buffer;

    add_build_error_decoration(buffer, real_coords_to_offset(buffer, last_build_error.coords));
    buffer.flags |= .needs_coloring;
}


last_build_error : Build_Error;
store_next_build_error := "";
build_error_exists := false;

Build_Error :: struct {
    path : string;
    coords : Coords;
    message : string;
    decorated_buffer : *Buffer;
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
}

// Must match the order of the types in the enum
COLOR_MAP :: Code_Color.[
    .CONSOLE_TEXT,  // plain
    .STRING,        // location
    .CONSOLE_ERROR,  // error
];

highlight_console_output :: (buffer: *Buffer, start_index: s32, count: s32, lang: Language) {
    if lang == {
        case .Jai;
        highlight_console_jai_output(buffer, start_index, count);

        case .Focus_Config;
        highlight_console_focus_config(buffer, start_index, count);
    }
}

set_color :: (s: string, color: Color) #expand {
    offset := s.data - `first_u8_byte;
    memset(`first_color_byte + offset, xx COLOR_MAP[color], s.count);
}

highlight_console_focus_config :: (buffer: *Buffer, start_index: s32, count: s32) {
    highlight_focus_config_syntax(buffer, start_index, count);
    add_buffer_region(buffer, start_index, start_index + count, false, 1, .todo_definitely_todo_this);
}

highlight_console_jai_output :: (buffer: *Buffer, start_index: s32, count: s32) {
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

    for line: line_split(s) {
        if !line {
            if !code_start
                code_start = line.data;
            continue;
        }

        if line[0] <= #char " " {
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

        sentinel :: ": Error: ";
        sentinel_colors :: Code_Color.[COLOR_MAP[Color.plain], COLOR_MAP[Color.plain], COLOR_MAP[Color.error], COLOR_MAP[Color.error], COLOR_MAP[Color.error], COLOR_MAP[Color.error], COLOR_MAP[Color.error], COLOR_MAP[Color.plain], COLOR_MAP[Color.plain]];
        #assert sentinel.count == sentinel_colors.count;

        if contains(line, sentinel) {
            location, message := split_into_two(line, sentinel);
            set_color(location, .location);
            sentinel_start := location.data + location.count - first_u8_byte;
            memcpy(first_color_byte + sentinel_start, sentinel_colors.data, sentinel_colors.count);
            set_color(message, .plain);

            //coord_start := last_index(location, #char ":");
            //coords := slice(location, coord_start + 1);
        }
        else {
            set_color(line, .plain);
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

