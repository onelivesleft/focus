console_initialized := false;

init_console :: () {
    init_output_buffer();

    console_thread_group = .{};
    init(*console_thread_group, 1, group_proc = console_threadproc);
    console_thread_group.name = "Console";
    console_thread_group.logging = false;
    for * console_thread_group.worker_info { it.thread.starting_context.logger_data = context.logger_data; }

    start(*console_thread_group);
    console_initialized = true;
}

init_output_buffer :: () {
    output_buffer = find_or_create_an_empty_buffer();
    buffer := *open_buffers[output_buffer];
    buffer.flags |= .readonly | .ignore | .manual_coloring;
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

print_to_console :: (output: string, append_newline: bool, lang: Language) {
    assert(output_buffer >= 0 && open_buffers.count > output_buffer, "output_buffer: %  buffer count: %", output_buffer, open_buffers.count);
    buffer := *open_buffers[output_buffer];
    start := cast(s32) buffer.bytes.count;

    s := ifx append_newline then tprint("%\n", output) else output;
    insert_string_raw(buffer, buffer.bytes.count, s, false);
    rescan_for_lines(buffer);
    recalculate_colors(buffer); // resizes color array
    highlight_console_output(buffer, start, cast(s32)buffer.bytes.count - start, lang);

    editors_open_buffer(output_buffer, .floating);
    editor := *open_editors[editors.floating];
    cursor := leave_only_original_cursor(editor);
    cursor.pos = xx buffer.bytes.count;
    cursor.sel = cursor.pos;
    add_paste_animation(editor, get_selection(cursor));
    editor.cursor_moved = .unimportant;
    editor.scroll_to_cursor = .yes;
}

print_console_header :: (s: string, leading_newline := true) {
    assert(output_buffer >= 0 && open_buffers.count > output_buffer, "output_buffer: %  buffer count: %", output_buffer, open_buffers.count);
    buffer := *open_buffers[output_buffer];
    if leading_newline  print_to_console("\n");
    start := cast(s32) buffer.bytes.count;
    print_to_console(s, true);
    end := cast(s32) buffer.bytes.count - 1;
    memset(buffer.colors.data + start, xx Code_Color.CONSOLE_HEADER_TEXT, end - start);
    add_buffer_region(buffer, start, end, true, 1, .console_header);
}

clear_console :: (header := "") {
    assert(output_buffer >= 0 && open_buffers.count > output_buffer, "output_buffer: %  buffer count: %", output_buffer, open_buffers.count);
    buffer := *open_buffers[output_buffer];
    clear_buffer(buffer);
    if header  insert_string_raw(buffer, buffer.bytes.count, header, false);
    rescan_for_lines(buffer);
    editors_open_buffer(output_buffer, .floating);
}

show_console :: () {
    editors_open_buffer(output_buffer, .floating);
}

hide_console :: () {
    editors.floating = -1;
}

toggle_console :: () {
    if editors.floating >= 0  hide_console();
    else                      show_console();
}

build :: (mode : Build_Mode) {
    if build_task_running  return;

    using config := *build_configs[mode];

    if random_build_icon_set  build_icon_set = xx random_int(xx #run enum_highest_value(type_of(build_icon_set)) + 1);
    if #complete build_icon_set == {
        case .dumpster_fire; build_icons = dumpster_icons;
        case .hourglass;     build_icons = hourglass_icons;
        case .poop;          build_icons = poop_icons;
        case .scales;        build_icons = scales_icons;
    }

    clear_user_messages(.build);

    if !enabled {
        add_user_error(tprint("You must supply a % section in your project config.", workspace_subsection_from_build_mode(mode)), origin=.build);
        return;
    }

    save_all(null, null, false);

    task := New(Console_Task, allocator=console_allocator);
    task.title = copy_string(tprint(build_mode_labels[mode], name), console_allocator);
    task.build_config = build_configs[mode];

    add_work(*console_thread_group, task, task.title);
}

build_task_running := false;

console_threadproc :: (group: *Thread_Group, thread: *Thread, work: *void) -> Thread_Continue_Status {
    using task := cast(*Console_Task) work;

    if build_error_exists {
        if last_build_error.decorated_buffer
            last_build_error.decorated_buffer.flags |= .needs_coloring;
        build_error_exists = false;
    }
    store_next_build_error = task.title;
    build_task_running = true;
    defer build_task_running = false;
    remove_delayed_action(hide_console);

    print_console_header(task.title);

    successful := true;
    output: string;
    error: string;

    for command: task.build_config.commands {
        if output  free(output);
        if error  free(error);

        print("\n\n\n\n\n");

        result, output=, error=, timed_out := run_command(
            .. break_command_into_strings(command),
            working_directory = task.build_config.working_directory,
            capture_and_return_output = true,
            output_callback = print_to_console,
            error_callback = on_error
        );

        if result.exit_code {
            successful = false;
            break;
        }
    }

    defer { free(error); free(output); }

    if successful {
        duration : float64 : 5;
        add_success_message(tprint("% Success!", task.title), origin=.build, dismiss_in_seconds = duration);
        if HIDE_CONSOLE_ON_SUCCESS  add_delayed_action(hide_console, duration);
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
            store_next_build_error = "";
            #if AUTO_JUMP_TO_ERROR  jump_to_error();
        }
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

Build_Config :: struct {
    name : string;
    working_directory : string;
    commands : [..] string;
    enabled : bool;
}

Build_Mode :: enum {
    DEBUG;
    RELEASE;
    DEBUG_AND_RUN;
    RELEASE_AND_RUN;
    RUN_DEBUG;
    RUN_RELEASE;
}

build_configs : [6] Build_Config;
build_mode_labels :: string.["% [Build: Debug]", "[%] Build: Release", "[%] Build: Debug and Run", "[%] Build: Release and Run", "[%] Run Debug", "[%] Run Release"];

reset_build_configs :: () {
    for * config: build_configs {
        if config.name  free(config.name.data, console_allocator);
        config.name = "";

        if config.working_directory  free(config.working_directory.data, console_allocator);
        config.working_directory = "";

        for * command: config.commands
            free(command.data, console_allocator);
        array_reset(*config.commands);

        config.enabled = false;
    }
}

validate_build_configs :: () -> error: string {
    for config: build_configs {
        if !config.enabled  continue;
        if !config.name  return "Must provide  name:";
        if !config.working_directory  return "Must provide  dir:";
        if config.commands.count == 0  return "Must provide one or more  command:";
    }
    return "";
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


#scope_file

Console_Task :: struct {
    title : string;
    build_config : Build_Config;
}

output_buffer : s64 = -1;

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
    }
}

set_color :: (s: string, color: Color) #expand {
    offset := s.data - `first_u8_byte;
    memset(`first_color_byte + offset, xx COLOR_MAP[color], s.count);
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
        s : string = ---;
        s.data = `buffer.bytes.data + start;
        s.count = end - start;
        i, found := last_index(s, #char "^");
        if found  `buffer.colors[start + i] = xx COLOR_MAP[Color.error];
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
