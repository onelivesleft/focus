ficus_allocator: Allocator;
ficus_pool: Flat_Pool;

Space :: enum { none; baked; global; project; user; }
Volume :: enum { silent; errors; default; verbose; }

Stack_Item :: struct {
    type : enum {
        boolean;
        word;
        int_number;
        number;
        text;
        sequence;
        error;
        separator;
        type;
    }

    string_value: string;

    #place string_value;
    int_value: s64;
    value: float32;
    bool_value: bool;
}

init_ficus :: () {
    main_stack_color = *Colors.UI_BACKGROUND_0;
    user_stack_colors[0] = *Colors.UI_BACKGROUND_1;
    user_stack_colors[1] = *Colors.UI_BACKGROUND_2;
    user_stack_colors[2] = *Colors.UI_BACKGROUND_3;
    user_stack_colors[3] = *Colors.UI_BACKGROUND_4;
    user_stack_colors[4] = *Colors.UI_BACKGROUND_5;

    ficus_execute_string(baked_words_string, .baked, .silent, null);

    for name, index: ACTIONS_EDITORS
        table_set(*action_words, unique_string(tprint("!%", name)), xx index);
}

ficus_run :: () {
    is_ficus_debugging = false;
    ficus_machine_state = .continue_running;
}

ficus_step_into :: () {
    is_ficus_debugging = true;
    ficus_machine_state = .step_into;
}

ficus_step_over :: () {
    is_ficus_debugging = true;
    ficus_machine_state = .step_over;
}

ficus_pause :: () {
    is_ficus_debugging = true;
    ficus_machine_state = .pause_request;
}

ficus_halt :: () {
    is_ficus_debugging = false;
    ficus_started_running_frame_count = 0;
    array_reset(*ficus_execution_stack);
    array_reset(*ficus_scripts_to_execute);
    reset_environment();
}

is_ficus_running :: inline () -> bool {
    return ficus_execution_stack || ficus_scripts_to_execute;
}

is_ficus_paused :: inline () -> bool {
    return ficus_machine_state >= .paused;
}

ficus_instruction_pointer : struct {
    buffer_id := -1;
    offset_from_buffer_start: s32;
    len: s32;
}

ficus_started_running_frame_count := 0;

ficus_update :: () {
    if !is_ficus_running() && ficus_calculator_text != ficus_prev_calculator_text {
        if ficus_prev_calculator_text  free(ficus_prev_calculator_text);
        ficus_prev_calculator_text = copy_string(ficus_calculator_text);
        ficus_execute_string(ficus_calculator_text, output = .silent);
        is_error, result := ficus_tick(true);
        calculator_result(is_error, result);
    }

    if !is_ficus_running()
         ficus_execute_event("on_frame");

    ficus_tick();
}

ficus_tick :: (request_result := false) -> is_error: bool, result: string {
    if !is_ficus_running()
        return false, "";

    if ficus_started_running_frame_count == 0
        ficus_started_running_frame_count = frame_count;

    if editors.active >= 0 {
        editor := *open_editors[editors.active];
        ficus_icon :: "\uf06c";
        play_icon :: "\uf04b";
        pause_icon :: "\uf04c";
        if !is_ficus_debugging && frame_count > ficus_started_running_frame_count {
            add_status_part(editor, .icon, ficus_icon);
            add_status_part(editor, .text, "Ficus");
            if #complete ficus_machine_state == {
                case .running; #through;
                case .continue_running; #through;
                case .step_into;
                case .step_over;
                    add_status_part(editor, .icon, play_icon);

                case .paused; #through;
                case .pause_request; #through;
                case .pause_just_happened;
                    add_status_part(editor, .icon, pause_icon);
            }
            add_status_part(editor, .divider, "");
        }
    }

    if ficus_machine_state == .paused
        return false, "";

    if !ficus_execution_stack {
        item := *ficus_scripts_to_execute[0];
        execute_string(item.script, *main_stack, item.space, item.output);
    }

    for instruction_count: 1 .. max_instructions_per_frame {
        state, error, result := execute_one_frame(request_result);

        if state == .errored {
            if ficus_execution_stack.count > 0 {
                if config.settings.ficus_debug_on_error && !request_result {
                    frame := *ficus_execution_stack[ficus_execution_stack.count - 1];
                    frame.token = frame.previous_token;
                    frame.tokenizer = frame.previous_tokenizer;
                    ficus_machine_state = .pause_just_happened;
                    state = .active;
                    is_ficus_debugging = true;
                }
                else {
                    ficus_halt();
                    return true, error;
                }
            }
        }

        if state == .active {
            if ficus_machine_state == .pause_just_happened && ficus_execution_stack {
                update_instruction_pointer :: (new_buffer_id: int, buffer_offset : s32 = 0) #expand {
                    using ficus_instruction_pointer;
                    if new_buffer_id < 0  return;
                    if buffer_id != new_buffer_id && buffer_id >= 0
                        open_buffers[buffer_id].flags |= .needs_coloring;
                    buffer_id = new_buffer_id;
                    offset_from_buffer_start = xx (`about_to_execute_word.data - `container.data) + buffer_offset;
                    len = xx `about_to_execute_word.count;
                    open_buffers[buffer_id].flags |= .needs_coloring;
                }
                container, stored_within := ficus_stored_string(about_to_execute_word);
                if #complete stored_within == {
                    case .baked;
                    open_baked_words_buffer();
                    editor := *open_editors[editors.active];
                    update_instruction_pointer(editor.buffer_id);
                    jump_to_offset(editor, xx (about_to_execute_word.data - container.data));
                    ficus_machine_state = .paused;

                    case .global;
                    update_instruction_pointer(get_global_words_buffer_id(), global_words_buffer_offset);
                    jump_to_file_offset(global_words_filename, global_words_buffer_offset + xx (about_to_execute_word.data - container.data));
                    ficus_machine_state = .paused;

                    case .project;
                    update_instruction_pointer(get_project_words_buffer_id(), project_words_buffer_offset);
                    jump_to_file_offset(project_words_filename, project_words_buffer_offset + xx (about_to_execute_word.data - container.data));
                    ficus_machine_state = .paused;

                    case .user;
                    update_instruction_pointer(user_words_buffer_id);
                    jump_to_file_offset(user_words_filename, xx (about_to_execute_word.data - container.data));
                    ficus_machine_state = .paused;

                    case .none; #through;
                    case;
                    console_log(tprint("<%> Internal: %", ficus_execution_stack.count, about_to_execute_word));
                    ficus_machine_state = .paused;
                }
                break;
            }

            if ficus_machine_state == .step_into || ficus_machine_state == .step_over {
                if ficus_machine_state == .step_over
                    ficus_pause_depth = ficus_execution_stack.count;
                ficus_machine_state = .pause_request;
            }
            else if ficus_machine_state == .continue_running
                ficus_machine_state = .running;
        }
        else {
            array_reset(*ficus_execution_stack);
            finished := *ficus_scripts_to_execute[0];
            if finished.callback  finished.callback(error);
            inserted_event := false;
            if finished.event {
                words := words_for_space(finished.space);
                word := table_find_pointer(words, finished.event);
                if word {
                    finished.script = word.*;
                    finished.event = "";
                    inserted_event = true;
                }
            }
            if !inserted_event
                array_ordered_remove_by_index(*ficus_scripts_to_execute, 0);

            if ficus_scripts_to_execute {
                item := *ficus_scripts_to_execute[0];
                execute_string(item.script, *main_stack, item.space, item.output);
            }
            else {
                ficus_halt();
                return false, result;
            }
        }
    }
    return false, "";
}

ficus_draw_ui :: () {
    if !is_ficus_running() || !is_ficus_debugging
        return;

    using font_data;
    position := make_vector2(char_x_advance, char_x_advance);
    stack_width :: 140.0;
    stack_margin :: 2;
    border_size :: 2;

    stack_icon :: "\uf1c0";
    ficus_icon :: "\uf06c";
    play_icon :: "\uf04b";
    pause_icon :: "\uf04c";

    // data stacks
    draw_stack :: (stack: *[..] Stack_Item, title: string, position: Vector2, color: Color, left_icon := stack_icon, right_icon := "") {
        using font_data;
        rect := Rect.{position.x, position.y, stack_width, font_ui_line_height};
        border := expand(rect, border_size);
        draw_cool_rect(border, with_alpha(Colors.UI_DEFAULT, 0.5), 0.5);
        draw_icon_text_rect(rect, color, Colors.UI_DEFAULT, left_icon, title, right_icon);
        rect.y += rect.h + stack_margin + border_size;
        if stack.count == 0 {
            rect.h *= 0.25;
            draw_icon_text_rect(rect, color, Colors.UI_DEFAULT, "", "", "");
        }
        else {
            for stack.* {
                h := draw_stack_item_rect(rect, color, Colors.UI_DEFAULT, it);
                rect.y += h + stack_margin;
            }
        }
    }

    draw_stack(*main_stack, tprint("Ficus [%]", ficus_execution_stack.count), position, main_stack_color, ficus_icon, ifx is_ficus_paused() then pause_icon else play_icon);
    color_index := 0;
    for 0 .. user_stack_count - 1 {
        position.x += stack_width + stack_margin + border_size * 2;
        color_index = it % user_stack_colors.count;
        draw_stack(*user_stacks[it], user_stack_names[it], position, user_stack_colors[color_index]);
    }

    /*
    draw_jump_stack :: (stack: [] int, title: string, position: Vector2, color: Color, left_icon := stack_icon, right_icon := "") {
        using font_data;
        rect := Rect.{position.x, position.y, stack_width, font_ui_line_height};
        border := expand(rect, border_size);
        draw_cool_rect(border, with_alpha(Colors.UI_DEFAULT, 0.5), 0.5);
        draw_icon_text_rect(rect, color, Colors.UI_DEFAULT, left_icon, title, right_icon);
        rect.y += rect.h + stack_margin + border_size;
        if stack.count == 0 {
            rect.h *= 0.25;
            draw_icon_text_rect(rect, color, Colors.UI_DEFAULT, "", "", "");
        }
        else {
            for stack {
                draw_icon_text_rect(rect, color, Colors.UI_DEFAULT, "", tprint("%", it), "");
                rect.y += rect.h + stack_margin;
            }
        }
    }

    if ficus_execution_stack.count > 0 {
        frame := *ficus_execution_stack[ficus_execution_stack.count - 1];
        if frame.jump_stack {
            position.x += stack_width + stack_margin + border_size * 2;
            color_index = (color_index + 1) % user_stack_colors.count;
            draw_jump_stack(frame.jump_stack, "-jump-", position, user_stack_colors[color_index], "\uf090", "");
        }
    }
    */

    // execution stack

    // execution queue
}

draw_stack_item_rect :: (rect: Rect, background_color: Color, foreground_color: Color, item: Stack_Item) -> height: float {
    left_icon : string = ---;
    if #complete item.type == {
        case .word;        left_icon = "\u0077";
        case .text;        left_icon = "\uf10d";
        case .sequence;    left_icon = "";
        case .int_number;  left_icon = "\uf129";
        case .number;      left_icon = "\ue184";
        case .boolean;     left_icon = ifx item.bool_value then "\uf205" else "\uf204";
        case .error;       left_icon = "\uf188";
        case .separator;   left_icon = ""; // drawn different
        case .type;        left_icon = "\U0001f3f7";
    }
    if item.type == .separator {
        r := rect;
        r.h = 2;
        draw_icon_text_rect(r, with_alpha(foreground_color, 0.5), foreground_color, "", "", "");
        return r.h;
    }
    else {
        draw_icon_text_rect(rect, background_color, foreground_color, left_icon, to_display_string(item), "");
        return rect.h;
    }
}

ficus_reset_space :: (space: Space) {
    if space == {
        case .global;
        table_reset(*global_words);
        array_reset(*ACTIONS_SCRIPT);

        case .project;
        table_reset(*project_words);
        ACTIONS_SCRIPT.count = actions_script_global_cutoff;
    }
}

ficus_breakpoints : [..] Ficus_Breakpoint;

ficus_toggle_breakpoint :: (editor: *Editor, using buffer: *Buffer) {
    if !bytes.count  return;

    cursor := editor.cursors[editor.main_cursor];
    i := cursor.pos;

    breakpoint_token: Ficus_Token = ---;
    ok := false;
    space: Space;

    if id == baked_words_buffer_id {
        space = .baked;
        breakpoint_token, ok = ficus_executable_token_at_offset(baked_words_string, i);
    }
    else if id == global_words_buffer_id {
        space = .global;
        breakpoint_token, ok = ficus_executable_token_at_offset(global_words_string, i - global_words_buffer_offset);
    }
    else if id == project_words_buffer_id {
        space = .project;
        breakpoint_token, ok = ficus_executable_token_at_offset(project_words_string, i - project_words_buffer_offset);
    }
    else {
        space = .user;
        breakpoint_token, ok = ficus_executable_token_at_offset(cast(string)bytes, i);
    }

    if !ok  return;

    for ficus_breakpoints {
        if it.buffer_id == id && it.offset == breakpoint_token.start {
            remove it;
            flags |= .needs_coloring;
            return;
        }
    }

    breakpoint := array_add(*ficus_breakpoints);
    breakpoint.space = space;
    breakpoint.buffer_id = id;
    breakpoint.offset = breakpoint_token.start;
    breakpoint.len = breakpoint_token.len;

    if space == {
        case .baked;    breakpoint.host_string = baked_words_string;
                        breakpoint.offset_from_buffer_start = breakpoint.offset;

        case .global;   breakpoint.host_string = global_words_string;
                        breakpoint.offset_from_buffer_start = breakpoint.offset + global_words_buffer_offset;

        case .project;  breakpoint.host_string = project_words_string;
                        breakpoint.offset_from_buffer_start = breakpoint.offset + project_words_buffer_offset;

        case .user;     breakpoint.host_string = "";
                        breakpoint.offset_from_buffer_start = breakpoint.offset;
    }

    flags |= .needs_coloring;
}

ficus_execute_editor :: (editor: *Editor, buffer: *Buffer, output := Volume.default, $loc := #caller_location) {
    if buffer.id == baked_words_buffer_id  return;
    ficus_set_user_words_string(cast(string) buffer.bytes, buffer.file.full_path, buffer.id);
    array_add(*ficus_scripts_to_execute, .{user_words_string, "", .user, output, ficus_execute_editor_finished_callback});
    ficus_machine_state = .running;
}

ficus_execute_editor_or_continue :: (editor: *Editor, buffer: *Buffer, output := Volume.default, $loc := #caller_location) {
    if is_ficus_running()
        ficus_run();
    else
        ficus_execute_editor(editor, buffer, output);
}

ficus_execute_editor_or_step :: (editor: *Editor, buffer: *Buffer, output := Volume.default, $loc := #caller_location) {
    if is_ficus_running() {
        ficus_step_over();
    }
    else {
        ficus_execute_editor(editor, buffer, output);
        ficus_pause();
    }
}

ficus_execute_string :: (script: string, space := Space.user, output := Volume.default, callback: #type (string) = null, $event := "", $loc := #caller_location) {
    #assert event == "" || array_find(ficus_events, event);

    array_add(*ficus_scripts_to_execute, .{script, event, space, output, callback});
    ficus_machine_state = .running;
}

ficus_execute_delayed_string :: (script_pointer: *void) {
    script := to_string(cast(*u8)script_pointer);
    array_add(*ficus_scripts_to_execute, .{unique_string(script, true), "", .user, .default, null});
    ficus_machine_state = .running;
}

ficus_execute_event :: ($event: string) {
    #assert array_find(ficus_events, event);
    if is_ficus_debugging  return;

    word, found := get_word(event);
    if found
        ficus_execute_string(word);
}

run_build_script :: (mode: enum { Compile; Debug; Release; }) {
    word_name := ifx mode == .Compile
                 then "compile"
                 else ifx mode == .Release
                      then "build_release"
                      else "build_debug";
    word, found := get_word(word_name);
    if !found {
        print_console_header("[BUILD] Missing script", is_error = true);
        print_to_console(tprint("You must define a '%' script in your project's [[script]] section.  For example:\n", word_name));
        print_to_console(tprint(#string focus_config

[[script]]

%:
    "% - %" build_name!
    "c:\jai\bin\jai.exe first.jai" build
focus_config, word_name, current_project_name, mode), .Focus_Config);
        return;
    }

    ficus_execute_string(word, .user, .default, build_finished_callback);
}

ficus_stored_string :: (s: string) -> string, Space {
    if is_within(s, baked_words_string)    return baked_words_string, .baked;
    if is_within(s, global_words_string)   return global_words_string, .global;
    if is_within(s, project_words_string)  return project_words_string, .project;
    if is_within(s, user_words_string)     return user_words_string, .user;
    return "", .none;
}

ficus_set_global_words_string :: (s: string, filename: string, offset: s32) -> string {
    //print_to_console("\nSETTING GLOBAL\n");
    if s != global_words_string {
        if global_words_string  free(global_words_string);
        global_words_string = copy_string(s);
    }
    global_words_filename = filename;
    global_words_buffer_offset = offset;
    return global_words_string;
}

ficus_set_project_words_string :: (s: string, filename: string, offset: s32) -> string {
    if s != project_words_string {
        if project_words_string  free(project_words_string);
        project_words_string = copy_string(s);
    }
    project_words_filename = filename;
    project_words_buffer_offset = offset;

    return project_words_string;
}

ficus_set_user_words_string :: (s: string, filename: string, buffer_id: int) -> string {
    user_words_cache_index = (user_words_cache_index + 1) % cached_user_words_count;
    if user_words_cache[user_words_cache_index] {
        free(user_words_cache[user_words_cache_index]);
    }
    user_words_cache[user_words_cache_index] = copy_string(s);
    user_words_string = user_words_cache[user_words_cache_index];
    user_words_filename = filename;
    user_words_buffer_id = buffer_id;
    return user_words_string;
}

is_within :: (needle: string, haystack: string) -> bool {
    return haystack.data <= needle.data && needle.data < haystack.data + haystack.count;
}

unique_string :: (s: string, force_store := false) -> string {
    if !force_store {
        already_stored_in := ficus_stored_string(s);
        if already_stored_in  return s;
    }

    result : string = ---;
    result.count = s.count;
    buffer_location_lookup := table_find_pointer(*ficus_string_lookup, s);
    if buffer_location_lookup {
        result.data = buffer_location_lookup.*;
    }
    else {
        result.data = alloc(s.count, ficus_allocator);
        memcpy(result.data, s.data, s.count);
        table_add(*ficus_string_lookup, result, result.data);
    }
    assert(xx ficus_allocator.proc(.IS_THIS_YOURS, 0, 0, result.data, ficus_allocator.data));
    return result;
}

open_baked_words_buffer :: () {
    buffer : *Buffer = ---;
    if baked_words_buffer_id < 0 {
        baked_words_buffer_id = find_or_create_an_empty_buffer();
        buffer = *open_buffers[baked_words_buffer_id];
        buffer.flags |= .readonly | .ignore;
        buffer.file.name = "<ficus baked words>";
        buffer.file.icon = .fig;
        buffer.lang = .Ficus;
        insert_string_raw(buffer, buffer.bytes.count, baked_words_string, false);
        rescan_for_lines(buffer);
        recalculate_colors(buffer);
    }
    editors_open_buffer(baked_words_buffer_id);
}

ficus_finished_global_config_callback :: (error: string) {
    for editor: open_editors {
        if editor.buffer_id < 0  continue;
        buffer := *open_buffers[editor.buffer_id];
        if platform_path_equals(buffer.file.full_path, global_config_path) {
            buffer.flags |= .needs_coloring;
        }
    }
}

ficus_finished_project_config_callback :: (error: string) {
    for editor: open_editors {
        if editor.buffer_id < 0  continue;
        buffer := *open_buffers[editor.buffer_id];
        if platform_path_equals(buffer.file.full_path, project_config_path) {
            buffer.flags |= .needs_coloring;
        }
    }
}

get_global_words_buffer_id :: inline () -> int {
    if global_words_buffer_id < 0
        global_words_buffer_id = find_or_create_buffer(global_words_filename);
    return global_words_buffer_id;
}

get_project_words_buffer_id :: () -> int {
    if project_words_buffer_id < 0
        project_words_buffer_id = find_or_create_buffer(project_words_filename);
    return project_words_buffer_id;
}

ficus_calculator_text: string;
ficus_prev_calculator_text: string;

ficus_update_calculator_text :: (s: string) {
    if s != ficus_calculator_text {
        if ficus_calculator_text  free(ficus_calculator_text);
        ficus_calculator_text = copy_string(s);
    }
}

#scope_file

max_stack_size :: 4096;
max_user_stacks :: 64;
max_instructions_per_frame :: 8192;
max_stack_depth :: 256;
cached_user_words_count :: 24;

#insert -> string {
    b: String_Builder;
    baked_words, ok := read_entire_file("src/baked_words.fig");
    if !ok  compiler_report("Could not find/read ficus baked words file (src/baked_word.fig)", mode=.WARNING);
    print_to_builder(*b, #string jai
baked_words_string :: #string fig
%
fig;
    jai, baked_words);
    return builder_to_string(*b);
}

global_words_string : string;
project_words_string : string;
user_words_string : string;

user_words_cache : [cached_user_words_count] string;
user_words_cache_index := 0;

global_words_buffer_offset  : s32 = 0;
project_words_buffer_offset : s32 = 0;

baked_words_buffer_id := -1;
global_words_filename := "";
global_words_buffer_id := -1;
project_words_filename := "";
project_words_buffer_id := -1;
user_words_filename := "";
user_words_buffer_id := -1;

baked_words: Table(string, string);
global_words: Table(string, string);
project_words: Table(string, string);
user_words: Table(string, string);
action_words : Table(string, Action_Editors);
global_variables: Table(string, Stack_Item);

ficus_execution_stack : [..] Ficus_Frame;
main_stack: [..] Stack_Item;
user_stacks: [max_user_stacks] [..] Stack_Item;
user_stack_names: [max_user_stacks] string;
user_stack_count := 0;
main_stack_color : *Color;
user_stack_colors : [5] *Color;

move_tokens_to_expect_stack_count := 0;

ficus_global_flags : enum_flags {
    already_opened_project;
    displayed_header;
    break_next_jump;
}

ficus_machine_state : enum {
    running;
    continue_running;
    // <= .continue_running -> Running,  >= .paused -> Paused
    paused;
    pause_request;
    pause_just_happened;
    step_over;
    step_into;
}

ficus_pause_depth := 0;

is_ficus_debugging := false;

about_to_execute_word := "";

Ficus_Execution_State :: enum {
    stopped;
    errored;
    active;
}

jump_to_jump_target := false;

Ficus_Frame :: struct {
    tokenizer: Ficus_Tokenizer;
    token: Ficus_Token;
    previous_tokenizer: Ficus_Tokenizer;
    previous_token: Ficus_Token;
    stack: *[..] Stack_Item;
    jump_stack: [..] int;
    space: Space;
    output: Volume;
    words: *Table(string, string);
}

Ficus_Breakpoint :: struct {
    buffer_id: int;
    host_string: string;
    offset: s32;
    offset_from_buffer_start: s32;
    len: s32;
    space: Space;
}

ficus_scripts_to_execute : [..] struct {
    script: string;
    event: string;
    space: Space;
    output: Volume;
    callback: #type (error: string);
};

ficus_events :: string.["on_load", "on_editor", "on_frame"];

ficus_string_lookup: Table(string, *u8);


ficus_execute_editor_finished_callback :: (error: string) { }

reset_environment :: () {
    assert(ficus_execution_stack.count == 0);
    ficus_global_flags = 0;
    user_stack_count = 0;
    move_tokens_to_expect_stack_count = 0;
    jump_to_jump_target = false;
    clear_all_stacks();
    if ficus_instruction_pointer.buffer_id >= 0 {
        open_buffers[ficus_instruction_pointer.buffer_id].flags |= .needs_coloring;
        ficus_instruction_pointer.buffer_id = -1;
    }
}

console_log :: (s: string, word := "") {
    leader := "";
    if !(ficus_global_flags & .displayed_header) {
        print_console_header(tprint("[FICUS] %", frame_time));
        ficus_global_flags |= .displayed_header;
    }
    if word
        print_to_console(tprint("(%) {%}: %\n", main_stack.count, word, s));
    else
        print_to_console(tprint("(%): %\n", main_stack.count, s));
}

execute_string :: (s: string, stack : *[..] Stack_Item, space: Space, output: Volume) {
    if space == .none  return;

    if ficus_execution_stack.count == 0
        reset_environment();

    frame := array_add(*ficus_execution_stack);
    frame.token.type = .eol;
    frame.tokenizer = Ficus_Tokenizer.{s, s.data + s.count, s.data, s.data, false, false, frame.token};
    frame.stack = stack;
    frame.space = space;
    frame.output = output;
    frame.words = words_for_space(space);
}

execute_one_frame :: (request_result := false) -> Ficus_Execution_State, error: string, result: string {
    stack_depth := ficus_execution_stack.count;
    if stack_depth == 0  return .stopped, "", "";

    using frame := *ficus_execution_stack[stack_depth - 1];

    if stack_depth > max_stack_depth
        return .errored, tprint("Exceeded program stack depth limit (%)", max_stack_depth), "";

    ERRORS := output >= .errors;
    DEFAULT := output >= .default;
    VERBOSE := output >= .verbose;

    sequence_depth := 0;
    sequence_start: s32;
    sequence_is_empty: bool;

    error := "";
    token_string := "";

    using *tokenizer;

    if jump_to_jump_target {
        if !jump_stack {
            pop(*ficus_execution_stack);
            if !ficus_execution_stack
                return .errored, "No jump target found", "";
            else
                return .active, "", "";
        }
        jump_target := pop(*jump_stack);
        jump_to_jump_target = false;
        if ficus_global_flags & .break_next_jump {
            ficus_global_flags &= ~.break_next_jump;
        }
        else {
            if jump_target < 0  || jump_target > buf.count
                error = tprint("Bad jump target: %", jump_target);
            else
                t = buf.data + jump_target;
        }
    }

    previous_token = token;
    previous_tokenizer = tokenizer;

    is_ficus_stepping :: () -> bool #expand {
        return ficus_machine_state == .step_into || ficus_machine_state == .step_over;
    }

    pause_check :: () #expand {
        token_string : string = ---;
        token_string.data = buf.data + token.start;
        token_string.count = token.len;
        host_string, space := ficus_stored_string(token_string);
        should_pause := space && ficus_machine_state == .pause_request && (ficus_pause_depth == 0 || ficus_pause_depth >= stack_depth);
        if !should_pause && ficus_breakpoints && !is_ficus_stepping() && ficus_machine_state != .continue_running {
            // @TODO @Speed cache breakpoints per frame
            if space == .user {
                if user_words_buffer_id == -1  return;
                path := open_buffers[user_words_buffer_id].file.full_path;
                for ficus_breakpoints {
                    if it.offset_from_buffer_start == `token.start && it.space == .user && path == open_buffers[it.buffer_id].file.full_path {
                        should_pause = true;
                        break;
                    }
                }
            }
            else {
                for ficus_breakpoints {
                    if it.offset_from_buffer_start == `token.start && it.space == space {
                        should_pause = true;
                        break;
                    }
                }
            }
        }
        if should_pause {
            `token = previous_token;
            `tokenizer = previous_tokenizer;
            ficus_machine_state = .pause_just_happened;
            ficus_pause_depth = 0;
            `return .active, "", "";
        }
    }

    while !error {
        prev_token = token;
        is_start_of_line = prev_token.type == .eol;

        token = ficus_get_next_token(*tokenizer);
        if token.type == .eof  break;
        if token.type == .eol || token.type == .comment
            continue;

        token_as_string :: () -> string #expand {
            result : string = ---;
            result.data = buf.data + token.start;
            result.count = token.len;
            return result;
        }

        token_string = token_as_string();
        about_to_execute_word = token_string;
        assert(token.type != .word || token_string);

        if sequence_depth || (token.type != .begin_sequence && move_tokens_to_expect_stack_count) {
            added_token_to_stack := false;
            sequence_stack := ifx move_tokens_to_expect_stack_count
                              then get_stack("code")
                              else stack;
            if !sequence_depth && move_tokens_to_expect_stack_count {
                s : string = ---;
                s.data = buf.data + token.start;
                s.count = token.len;
                push_sequence(s, sequence_stack);
                added_token_to_stack = true;
            }
            else if token.type == {
                case .end_sequence;
                    sequence_depth -= 1;
                    if sequence_depth == 0 {
                        if sequence_is_empty {
                            push_empty_sequence(sequence_stack);
                        }
                        else {
                            s : string = ---;
                            s.data = buf.data + sequence_start;
                            s.count = token.start - sequence_start;
                            push_sequence(s, sequence_stack);
                        }
                        added_token_to_stack = true;
                    }

                case .begin_sequence;
                    sequence_depth += 1;

                case .error;
                    break;

                case .eol; #through;
                case .comment;
                    // no content

                case;
                    // content, so not empty
                    sequence_is_empty = false;
            }

            if move_tokens_to_expect_stack_count && added_token_to_stack {
                move_tokens_to_expect_stack_count -= 1;
                if !move_tokens_to_expect_stack_count {
                    execute_word("apply", frame, true);
                    return .active, "", "";
                }
            }

            continue;
        }

        if #complete token.type == {
            case .error;
                pause_check();
                error = "Parsing error";
                break;

            case .end_sequence;
                pause_check();
                error = "Unexpected ]";
                break;

            case .declaration;
                if token_string {
                    word_name := unique_string(token_string);
                    word, new := find_or_add(words, word_name);

                    token = ficus_get_next_token(*tokenizer);
                    assert(token_as_string() == ":");
                    definition_start := t;
                    ficus_skip_to_non_indented(*tokenizer);
                    definition_end := t;

                    definition : string = ---;
                    definition.data = definition_start;
                    definition.count = definition_end - definition_start;
                    word.* = definition;

                    if VERBOSE  console_log(tprint("Added word [%] with text: [%]", word_name, trim(word.*)), word_name);

                    token.type = .eol;
                }
                break;

            case .word; #through;
            case .word_with_stack;
                pause_check();
                execute_stack : *[..] Stack_Item = ---;
                word_name : string = ---;
                if token.type == .word_with_stack {
                    stack_name:, word_name = split_into_two(token_string, #char "'");
                    execute_stack = get_stack(stack_name);
                    if !execute_stack {
                        error = "Ran out of user stacks";
                        break;
                    }
                    execute_string(word_name, execute_stack, space, output);
                    return .active, "", "";
                }

                word_name = token_string;
                error = execute_word(word_name, frame);
                break;

            case .string_literal;
                pause_check();
                token_string.data += token.sublen;
                token_string.count -= token.sublen * 2;
                token_string = trim_through(token_string, #char "\n");
                push(token_string, stack);
                break;

            case .number_literal;
                pause_check();
                s := token_string;
                if contains(s, #char ".") {
                    float_value, ok := parse_float(*s);
                    if ok  push(float_value, stack);
                    else   error = tprint("We failed to parse a float [%], but we shouldn't have because the tokenizer should only tokenize floats!", token_as_string());
                }
                else {
                    int_value, ok := parse_int(*s);
                    if ok  push(int_value, stack);
                    else   error = tprint("We failed to parse an int [%], but we shouldn't have because the tokenizer should only tokenize ints!", token_as_string());
                }
                break;

            // previous sections should all break after - 1 thing has been executed
            // following sections should not break: they are no-ops, so we should go again

            case .begin_sequence;
                pause_check();
                sequence_start = token.start + 1;
                sequence_depth = 1;
                sequence_is_empty = true;

            case .eol; #through;
            case .comment;
            case .punctuation;  // syntax highlight only - can't happen
            case .string_error; // syntax highlight only - can't happen
            case .eof;          // will already break above - can't happen
        }
    }

    if !error {
        if sequence_depth
            error = "Expected ]";
        else if ficus_execution_stack.count == 1 && move_tokens_to_expect_stack_count
            error = tprint("Expected % more tokens", move_tokens_to_expect_stack_count);
    }

    if error {
        if ERRORS  console_log(error, token_string);
        return .errored, error, "";
    }

    if token.type == .eof {
        pop(*ficus_execution_stack);
        if !ficus_execution_stack {
            if request_result {
                builder: String_Builder;
                for main_stack {
                    if it_index  append(*builder, " ");
                    append(*builder, to_string(it));
                }
                result := builder_to_string(*builder, temp);
                return .stopped, "", result;
            }
            else {
                clear_all_stacks();
                return .stopped, "", "";
            }
        }
    }

    return .active, "", "";
}


popped_during_this_execute_word : [..] Stack_Item;


execute_word :: (word_name: string, frame: *Ficus_Frame, intrinsic_only := false) -> error: string {
    assert(!contains(word_name, #char "'")); // at this point the word should be resolved and not contain a stack reference

    using frame;

    ERRORS  := output >= .errors;
    DEFAULT := output >= .default;
    VERBOSE := output >= .verbose;

    defer {
        for < popped_during_this_execute_word  push(it, stack);
        array_reset(*popped_during_this_execute_word);
    }

    pop :: (t: type_of(Stack_Item.type), name := "") -> Stack_Item #expand {
        if !stack.count {
            if name
                `return tprint("% expected <%> for parameter '%' but stack was empty", word_name, t, name);
            else
                `return tprint("% expected <%> but stack was empty", word_name, t);
        }
        item := pop(stack);
        pop_message(item, stack);
        if t == .number {
            if item.type != .number && item.type != .int_number && item.type != .boolean {
                if name
                    `return tprint("% expected <%> for parameter '%' but found <%>", word_name, t, name, item.type);
                else
                    `return tprint("% expected <%> but found <%>", word_name, t, item.type);
            }
        }
        else {
            if item.type != t {
                if name
                    `return tprint("% expected <%> for parameter '%' but found <%>", word_name, t, name, item.type);
                else
                    `return tprint("% expected <%> but found <%>", word_name, t, item.type);
            }
        }
        return item;
    }

    pop :: (name := "") -> Stack_Item #expand {
        if !stack.count {
            if name
                `return tprint("% expected a value for parameter '%' but stack was empty", word_name, name);
            else
                `return tprint("% expected a value but stack was empty", word_name);
        }
        item := pop(stack);
        pop_message(item, stack);
        return item;
    }

    return_success :: () #expand {
        array_reset(*popped_during_this_execute_word);
        `return "";
    }

    if !intrinsic_only {
        word, found := get_word(word_name);
        if found {
            execute_string(word, stack, space, output);
            return_success();
        }

        handled:, found = try_handle_action_word(word_name);
        if found {
            if handled
                return_success();
            else
                return tprint("Error: Tried to perform action [%] but we failed to handle it.", word_name);
        }
    }

    handle_basic_operator :: (int_operator: (int, int)->$T, $U: Type = float, float_operator: (float,float)->U = null) #expand {
        b := pop();
        if !is_number(b)  `return tprint("% only work on numbers", `word_name);
        a := pop();
        if !is_number(a)  `return tprint("% only work on numbers", `word_name);
        if is_int_number(a) && is_int_number(b)
            push(cast(T)int_operator(a.int_value, b.int_value), stack);
        else if float_operator
            push(cast(U)float_operator(a.value, b.value), stack);
        else
            `return tprint("% does not work on numbers (just on int_numbers)", `word_name);
    }

    peek :: (name := "") -> Stack_Item #expand {
        if !stack.count {
            if name
                `return tprint("% expected a value for parameter '%' but stack was empty", word_name, name);
            else
                `return tprint("% expected a value but stack was empty", word_name);
        }
        return stack.*[stack.count - 1];
    }

    index_after_separator :: (_stack: *[..] Stack_Item = null) -> index: int, index_before_separator: int #expand {
        if !_stack  _stack = stack;
        for < i: _stack.count - 1 .. 0
            if _stack.*[i].type == .separator
                return i + 1, i;
        return 0, 0;
    }

    found_intrinsic := true;

    #insert,scope() intrinsics;

    if found_intrinsic
        return_success();

    if !intrinsic_only {
        if word_name.count > 1 && (word_name[word_name.count - 1] == #char "!" || word_name[word_name.count - 1] == #char "?") {
            variable_name := unique_string(word_name);
            variable_name.count -= 1;
            if word_name[word_name.count - 1] == #char "!" {
                item := pop();
                ptr := find_or_add(*global_variables, variable_name);
                ptr.* = item;
                return_success();
            }
            else {
                ptr := table_find_pointer(*global_variables, variable_name);
                if ptr {
                    push(ptr.*, stack);
                    return_success();
                }
            }
        }
    }

    return tprint("Could not find word [%]", word_name);
}

is_number :: (item: Stack_Item) -> bool {
    return item.type == .int_number || item.type == .number || item.type == .boolean;
}

is_int_number :: (item: Stack_Item) -> bool {
    return item.type == .int_number || item.type == .boolean;
}

is_executable :: (item: Stack_Item) -> bool {
    return item.type == .word || item.type == .sequence;
}

intrinsics :: #code if word_name == {
    // Word names have a very broad lattitude for characters, the only reserved characters are:
    //  [ ] ( ) # "

    // Conventions for naming:
    //   Do not start a word with !, as all the locus actions are loaded into words starting with !
    //   (for instance, `!copy` performs ctrl-c, while `copy` duplicates the last item on the stack)
    //   End words with a `?` if they return a value but do not consume any items from the stack
    //   End words with a `!` if they set something
    //   Control flow words operate against-the-grain of the language, being written prefix like
    //   in most other languages.  For example:
    //      if [2 1 >] ["Two is greater than One!" .]
    //   ...the condition and body follow the `if`.  However, sometimes the code might be written
    //   easier by using a postfix control flow word, so by convention every control flow word
    //   has a postfix twin, and it is named identically but with a period prefix.  So, the
    //   above can be written:
    //      ["Two is greater than One!" .] [2 1 >] .if

    case "true";
        push(true, stack);

    case "true?";
        value := pop();
        push(to_bool(value), stack);

    case "false";
        push(false, stack);

    case "false?";
        value := pop();
        push(!to_bool(value), stack);

    case "<number>";
        push_type(.number, stack);

    case "<text>";
        push_type(.text, stack);

    case "<word>";
        push_type(.word, stack);

    case "<boolean>";
        push_type(.boolean, stack);

    case "<error>";
        push_type(.error, stack);

    case "<separator>";
        push_type(.separator, stack);

    case "<sequence>";
        push_type(.sequence, stack);

    case "<type>";
        push_type(.type, stack);

    case "number?";
        if !is_number(peek())  return tprint("Type-checked for a number, found a %", peek().type);

    case "int_number?";
        if !is_int_number(peek())  return tprint("Type-checked for a number, found a %", peek().type);

    case "text?";
        if peek().type != .text  return tprint("Type-checked for a text, found a %", peek().type);

    case "boolean?";
        if peek().type != .boolean  return tprint("Type-checked for a boolean, found a %", peek().type);

    case "error?";
        if peek().type != .error  return tprint("Type-checked for a error, found a %", peek().type);

    case "separator?";
        if peek().type != .separator  return tprint("Type-checked for a separator, found a %", peek().type);

    case "sequence?";
        if peek().type != .sequence  return tprint("Type-checked for a sequence, found a %", peek().type);

    case "type?";
        push_type(.type, stack);

    case "type";
        item := pop();
        push_type(item.type, stack);

    case "cast";
        type := pop(.type, "type");
        item := pop("value");
        item.type = xx type.int_value;
        push(item, stack);

    case "stack_count?";
        push(stack.count, stack);

    case "+";
        b := pop();
        a := pop();
        if a.type == .text || b.type == .text {
            push(tprint("%1%2", to_string(a), to_string(b)), stack);
        }
        else {
            if !is_number(a)  return tprint("% only work on numbers or text", word_name);
            if !is_number(b)  return tprint("% only work on numbers or text", word_name);
            if is_int_number(a) && is_int_number(b)
                push(a.int_value + b.int_value, stack);
            else
                push(a.value + b.value, stack);
        }

    case "=";
        b := pop();
        a := pop();
        if is_number(a) && is_number(b) {
            if is_int_number(a) && is_int_number(b)
                push(a.int_value == b.int_value, stack);
            else
                push(a.value == b.value, stack);
        }
        else if a.type == b.type {
            if a.type == {
                case .type; #through;
                case .error;
                push(a.int_value == b.int_value, stack);

                case .separator;
                push(true, stack);

                case .word; #through;
                case .text; #through;
                case .sequence;
                push(a.string_value == b.string_value, stack);
            }
        }
        else {
            push(false, stack);
        }

    case "-";   handle_basic_operator((x, y) => x-y,  float_operator = (x, y) => x-y);
    case "*";   handle_basic_operator((x, y) => x*y,  float_operator = (x, y) => x*y);
    case "/";   handle_basic_operator((x, y) => x/y,  float_operator = (x, y) => x/y);
    case "<";   handle_basic_operator((x, y) => x<y,  bool, float_operator = (x, y) => x<y);
    case ">";   handle_basic_operator((x, y) => x>y,  bool, float_operator = (x, y) => x>y);
    case "<=";  handle_basic_operator((x, y) => x<=y, bool, float_operator = (x, y) => x<=y);
    case ">=";  handle_basic_operator((x, y) => x>=y, bool, float_operator = (x, y) => x>=y);
    case "%";   handle_basic_operator((x, y) => x%y, float_operator = (x, y) => fmod_cycling(x, y));
    case "&";   handle_basic_operator((x, y) => x&y);
    case "^";   handle_basic_operator((x, y) => x^y);
    case "|";   handle_basic_operator((x, y) => x|y);

    case "and"; handle_basic_operator((x, y) => x&&y, bool, float_operator = (x, y) => x&&y);
    case "or";  handle_basic_operator((x, y) => x||y, bool, float_operator = (x, y) => x||y);
    case "not";
        truth := to_bool(pop());
        push(!truth, stack);

    case "0-";
        value := pop();
        if value.type == .int_number
            push(0 - value.int_value, stack);
        else if value.type == .number
            push(0 - value.value, stack);
        else
            return tprint("% can only be used on numbers", word_name);

    case "\\"; // ficus_separator_name
        #assert("\\" == ficus_separator_name);
        push_separator(stack);

    case "pop";
        if stack == *main_stack {
            pop();
        }
        else {
            item := pop();
            push(item, *main_stack);
        }

    case "peek";
        if stack == *main_stack
            return "Cannot peek main stack (it would just be be a nop)";
        item := peek();
        push(item, *main_stack);

    case "push";
        if stack == *main_stack
            return "Cannot push onto main stack (which stack would the item come from?)";
        if !main_stack.count
            return tprint("% expected a value but stack was empty", word_name);
        item := pop(*main_stack);
        pop_message(item, *main_stack);
        push(item, stack);

    case "discard";
        item := pop();

    case "copy";
        item := peek();
        push(item, stack);

    case "rotate";
        z := pop("z");
        y := pop("y");
        x := pop("x");
        push(y, stack);
        push(z, stack);
        push(x, stack);

    case "at";
        index := pop(.int_number).int_value;
        if stack.count <= index
            return tprint("% tried to look at item % from bottom of stack, but the stack only has % items (the top item of the stack would be %)", word_name, index, stack.count, stack.count - 1);
        push(stack.*[index], stack);

    case "pick";
        index_back := pop(.int_number).int_value;
        if stack.count <= index_back
            return tprint("% tried to look at item % from top of stack, but the bottom item in the stack is item % (the top item of the stack would be 0)", word_name, index_back, stack.count - 1);
        push(stack.*[stack.count - index_back - 1], stack);

    case "swap";
        a := pop();
        b := pop();
        push(a, stack);
        push(b, stack);

    case "swap_at";
        a := pop(.int_number).int_value;
        b := pop(.int_number).int_value;
        if stack.count <= a
            return tprint("% tried to look at item % from bottom of stack, but the stack only has % items (the top item of the stack would be %)", word_name, a, stack.count, stack.count - 1);
        if stack.count <= b
            return tprint("% tried to look at item % from bottom of stack, but the stack only has % items (the top item of the stack would be %)", word_name, b, stack.count, stack.count - 1);
        t := stack.*[a];
        stack.*[a] = stack.*[b];
        stack.*[b] = t;

    case "assert_x";
        if stack.count < 3
            return tprint("Expected 3 items on the stack but only saw %", stack.count);

    case "assert_y";
        if stack.count < 2
            return tprint("Expected 3 items on the stack but only saw %", stack.count);

    case "assert_z";
        if stack.count < 1
            return tprint("Expected 3 items on the stack but only saw %", stack.count);

    case "panic";
        return "Panic!";

    case "reverse";
        index, found := index_after_separator();
        count := stack.count - index;
        last_index := stack.count - 1;
        for 0 .. count / 2 - 1 {
            i := it + index;
            j := last_index - it;
            t := stack.*[i];
            stack.*[i] = stack.*[j];
            stack.*[j] = t;
        }

    case "break";
        ficus_global_flags |= .break_next_jump;

    case "debug_break";
        ficus_pause();

    case "jump_target";
        if VERBOSE  console_log(tprint("Pushed jump target [%]", token.start));
        array_add(*jump_stack, token.start);

    case "jump";
        jump_to_jump_target = true;

    case "pop_jump_target";
        if !jump_stack.count  return tprint("Tried to % but the jump_stack is empty", word_name);
        pop(*jump_stack);

    case "expect_then_apply";
        if stack.count < 2
            return tprint("% needs (word, count) but the stack only has % items", word_name, stack.count);
        count := pop(.int_number).int_value;
        if count < 0 || count >= max_stack_size
            return tprint("Illegal value for %: %", word_name, count);
        move_tokens_to_expect_stack_count = count;

    case "apply";
        item := pop();
        if is_executable(item)
            execute_string(item.string_value, stack, space, output);
        else
            push(item, stack);

    case "assert";
        value := pop("value");
        if !to_bool(value)
            return "Assert failed!";

    case "code.if";
        // code stack is <condition> <then_body>
        execute_string("code'swap code'pop apply code.if_true", stack, space, output);

    case "code.if_true";
        // code stack is then_body, stack is true/false
        code_stack := get_stack("code");
        if code_stack.count == 0
            return tprint("% expected parameter 'then_body' but stack was empty", word_name);
        then_body := pop(code_stack);

        value := pop("value");
        if to_bool(value) {
            push(then_body, stack);
            execute_string("apply", stack, space, output);
        }

    case ".if";
        // stack is <then_body> <condition>
        execute_string("apply swap code'push code.if_true", stack, space, output);

    case "code.if_else";
        // code stack is <condition> <then_body> <else_body>
        execute_string("code'pop code'swap code'push code'swap code'pop apply code.if_else_true", stack, space, output); // execute condition

    case "code.if_else_true";
        // code stack is then_body else_body, stack is true/false
        code_stack := get_stack("code");
        if code_stack.count == 0
            return tprint("% expected parameter 'else_body' but stack was empty", word_name);
        else_body := pop(code_stack);

        if code_stack.count == 0
            return tprint("% expected parameter 'then_body' but stack was empty", word_name);
        then_body := pop(code_stack);

        value := pop("value");
        if to_bool(value)
            push(then_body, stack);
        else
            push(else_body, stack);
        execute_string("apply", stack, space, output);

    case ".if_else";
        // stack is <then_body> <else_body> <condition>
        execute_string("apply swap code'push swap code'push code'swap code.if_else_true", stack, space, output); // execute condition

    case "debug_print_stack";
        if DEFAULT {
            builder : String_Builder;
            for stack.* {
                append(*builder, to_display_string(it));
                append(*builder, " ");
            }
            console_log(builder_to_string(*builder), word_name);
        }

    case "clear";
        clear_stack(stack);

    case "globals?";
        for global_variables  push(it_index, stack);

    case "exists?";
        word := pop("variable");
        if !has_string_value(word)  return tprint("% expected a word but got a %", word_name, word.type);
        needle := word.string_value;
        if needle {
            last_char := needle[needle.count - 1];
            if last_char == #char "!" || last_char == #char "?"
                needle.count -= 1;
            if table_find_pointer(*global_variables, needle) {
                push(true, stack);
                return_success();
            }
        }
        push(false, stack);

    // math

    case "cos";
        x := pop(.number, "x");
        push(cos(x.value), stack);

    case "sin";
        x := pop(.number, "x");
        push(sin(x.value), stack);

    case "tan";
        x := pop(.number, "x");
        push(tan(x.value), stack);

    case "atan";
        x := pop(.number, "x");
        push(atan(x.value), stack);

    case "acos";
        x := pop(.number, "x");
        push(acos(x.value), stack);

    case "asin";
        x := pop(.number, "x");
        push(asin(x.value), stack);

    case "sqrt";
        x := pop(.number, "x");
        push(sqrt(x.value), stack);

    case "pow";
        x := pop(.number, "x");
        power := pop(.number, "power");
        push(pow(x.value, power.value), stack);

    case "exp";
        x := pop(.number, "x");
        push(exp(x.value), stack);

    case "log";
        x := pop(.number, "x");
        push(log(x.value), stack);

    case "random_int";
        high := pop(.int_number, "max");
        r := random_int(high.int_value);
        push(r, stack);

    case "random";
        push(cast(float)random_get(), stack);

    case "floor";
        x := pop(.number, "x").value;
        push(cast(int) x, stack);

    case "rgb_to_hsl";
        b := pop(.number, "blue").value;
        g := pop(.number, "green").value;
        r := pop(.number, "red").value;
        h, s, l := hsl_from_rgb(.{r=r, g=g, b=b});
        push(h, stack);
        push(s, stack);
        push(l, stack);

    case "hsl_to_rgb";
        l := pop(.number, "blue").value;
        s := pop(.number, "green").value;
        h := pop(.number, "red").value;
        color := rgb_from_hsl(h, s, l);
        push(color.r, stack);
        push(color.g, stack);
        push(color.b, stack);

    // utils

    case "words?";
        table_reset(*word_cache);
        for intrinsic_words  table_set(*word_cache, it, true);
        for baked_words      table_set(*word_cache, it_index, true);
        for global_words     table_set(*word_cache, it_index, true);
        for project_words    table_set(*word_cache, it_index, true);
        for user_words       table_set(*word_cache, it_index, true);
        for action_words     table_set(*word_cache, it_index, true);
        for word_cache       push_word(it_index, stack);

    case ".";
        console_log(to_display_string(pop()), word_name);

    case "print";
        index, new_count := index_after_separator();
        builder : String_Builder;
        for i: index .. stack.count - 1 {
            if DEFAULT {
                append(*builder, to_display_string(stack.*[i]));
                append(*builder, " ");
            }
        }
        stack.count = new_count;

        if DEFAULT  console_log(builder_to_string(*builder), word_name);
        else        reset(*builder);

    case "after_frames";
        count := pop(.int_number, "frames");
        action := unique_string(tprint("%\0", to_string(pop())), true);
        add_delayed_action(ficus_execute_delayed_string, action.data, count.int_value);

    case "after_seconds";
        seconds := pop(.number, "seconds");
        action := unique_string(tprint("%\0", to_string(pop())), true);
        add_delayed_action(ficus_execute_delayed_string, action.data, seconds.value);

    // strings

    case "to_string";
        item := pop();
        push(to_string(item), stack);

    case "concatenate";
        index, new_count := index_after_separator();
        builder : String_Builder;
        for i: index .. stack.count - 1 {
            append(*builder, to_string(stack.*[i]));
        }
        stack.count = new_count;
        push(builder_to_string(*builder), stack);

    case "join";
        joint := to_string(pop("joint"));
        index, new_count := index_after_separator();
        builder : String_Builder;
        for i: index .. stack.count - 1 {
            if i  append(*builder, joint);
            append(*builder, to_string(stack.*[i]));
        }
        stack.count = new_count;
        push(builder_to_string(*builder), stack);

    case "contains";
        needle := pop(.text, "needle");
        haystack := pop(.text, "haystack");
        push(contains(haystack.string_value, needle.string_value), stack);

    case "first_index";
        needle := pop(.text, "needle");
        haystack := pop(.text, "haystack");
        push(first_index(haystack.string_value, needle.string_value), stack);

    case "last_index";
        needle := pop(.text, "needle");
        haystack := pop(.text, "haystack");
        push(last_index(haystack.string_value, needle.string_value), stack);

    case "starts_with";
        needle := pop(.text, "needle");
        haystack := pop(.text, "haystack");
        push(starts_with(haystack.string_value, needle.string_value), stack);

    case "ends_with";
        needle := pop(.text, "needle");
        haystack := pop(.text, "haystack");
        push(ends_with(haystack.string_value, needle.string_value), stack);

    case "slice";
        n := pop(.number, "from_index");
        if !is_int_number(n)  return tprint("Expected an integer number for %", word_name);
        x := pop("to_index/text");
        if is_int_number(x) {
            s := pop(.text, "text");
            push_already_unique_string(slice(s.string_value, x.int_value, n.int_value), stack);
        }
        else if x.type == .text {
            push_already_unique_string(slice(x.string_value, n.int_value), stack);
        }
        else {
            return tprint("Expected an integer number or string for %", word_name);
        }

    case "split";
        splitter := pop(.text, "splitter").string_value;
        text := pop(.text, "text").string_value;
        for split(text, splitter)
            push_already_unique_string(it, stack);

    case "line_split";
        text := pop(.text, "text").string_value;
        for line_split(text)
            push_already_unique_string(it, stack);

    // Locus info

    case "version?";
        push(VERSION, stack);

    case "locus_executable?";
        push(executable_name, stack);

    case "frame_time?";
        push(cast(float)frame_time, stack);

    case "frame_count?";
        push(frame_count, stack);

    case "fps?";
        push(get_fps(), stack);

    case "locus_build?";
        if DEBUG push("debug", stack);
        else     push("release", stack);

    // Locus settings

    case "console_location!";
        floating_area_position = xx pop(.int_number).int_value;
    case "console_location?";
        push(cast(int)floating_area_position, stack);

    case "window_location!";
        height := pop(.int_number, "height");
        width := pop(.int_number, "width");
        y := pop(.int_number, "x");
        x := pop(.int_number, "y");
        platform_set_window_location(xx x.int_value, xx y.int_value, xx width.int_value, xx height.int_value);
    case "window_location?";
        window_x, window_y, window_width, window_height = get_window_position_and_size(window);
        push(window_x, stack);
        push(window_y, stack);
        push(window_width, stack);
        push(window_height, stack);

    // Locus commands

    case "open_project";
        item := pop(.text, "project");
        success: bool;
        if ficus_global_flags & .already_opened_project
            success = false;
        else
            success = open_project(to_string(item));
        push(success, stack);

    case "projects?";
        names := get_project_names();
        for names  push(it, stack);

    case "open_file";
        item := pop(.text, "file");
        success := editors_open_file(to_string(item));
        push(success, stack);

    case "open_files";
        opened := 0;
        while stack.count {
            if peek(.separator, stack) {
                pop();
                break;
            }
            item := pop(.text, "file");
            success := editors_open_file(to_string(item));
            if success  opened += 1;
        }
        push(opened, stack);

    case "build_name!";
        name := pop(.text, "name");
        ok := set_build_task_name(name.string_value);
        if !ok  return tprint("Cannot % while a build is already running", word_name);

    case "build_dir!";
        dir := pop(.text, "path");
        ok := set_build_task_dir(dir.string_value);
        if !ok  return tprint("Cannot % while a build is already running", word_name);

    case "build";
        index, new_count := index_after_separator();
        has_commands := false;
        for i: index .. stack.count - 1 {
            command := stack.*[i];
            if command.type != .text
                return tprint("% expected a command but got a %", word_name, command.type);
            ok := add_build_task_command(command.string_value);
            if !ok  return tprint("Cannot % while a build is already running", word_name);
            has_commands = true;
        }
        stack.count = new_count;
        if has_commands  build();
        else             return tprint("% expected a command", word_name);

    case "editor_path?";
        if editors.active >= 0 {
            editor := *open_editors[editors.active];
            if editor.buffer_id >= 0 {
                buffer := *open_buffers[editor.buffer_id];
                push(buffer.file.full_path, stack);
                return_success();
            }
        }
        push("", stack);

    case "editor_filename?";
        if editors.active >= 0 {
            editor := *open_editors[editors.active];
            if editor.buffer_id >= 0 {
                buffer := *open_buffers[editor.buffer_id];
                push(buffer.file.name, stack);
                return_success();
            }
        }
        push("", stack);

    case "editor_folder?";
        if editors.active >= 0 {
            editor := *open_editors[editors.active];
            if editor.buffer_id >= 0 {
                buffer := *open_buffers[editor.buffer_id];
                push(buffer.file.path, stack);
                return_success();
            }
        }
        push("", stack);

    case "editor_language?";
        if editors.active >= 0 {
            editor := *open_editors[editors.active];
            if editor.buffer_id >= 0 {
                buffer := *open_buffers[editor.buffer_id];
                push(unique_string(tprint("%", buffer.lang)), stack);
                return_success();
            }
        }
        push("", stack);

    case "zen_mode?";
        push(zen_mode, stack);

    case "zen_mode!";
        value := pop(.boolean, "enabled");
        set_zen_mode(value.bool_value);

    case "toast";
        seconds := pop(.number, "seconds");
        message := pop(.text, "message");
        icon := pop(.text, "icon");
        add_user_message(message.string_value, xx seconds.value, icon.string_value, .ficus);

    case "toast_success";
        seconds := pop(.number, "seconds");
        message := pop(.text, "message");
        icon := pop(.text, "icon");
        add_user_message_success(message.string_value, xx seconds.value, icon.string_value, .ficus);

    case "toast_warning";
        seconds := pop(.number, "seconds");
        message := pop(.text, "message");
        icon := pop(.text, "icon");
        add_user_message_warning(message.string_value, xx seconds.value, icon.string_value, .ficus);

    case "toast_error";
        seconds := pop(.number, "seconds");
        message := pop(.text, "message");
        icon := pop(.text, "icon");
        add_user_message_error(message.string_value, xx seconds.value, icon.string_value, .ficus);

    case "status_bar_icon";
        if editors.active < 0  return "";
        icon := pop(.text, "icon");
        editor := *open_editors[editors.active];
        add_status_part(editor, .icon, icon.string_value);

    case "status_bar_text";
        if editors.active < 0  return "";
        text := pop(.text, "text");
        editor := *open_editors[editors.active];
        add_status_part(editor, .text, text.string_value);

    case "status_bar_divider";
        if editors.active < 0  return "";
        editor := *open_editors[editors.active];
        add_status_part(editor, .divider);

    // nada
    case;
        found_intrinsic = false;
}

intrinsic_words :: #insert -> string { // is: string.[]
    builder: String_Builder;
    append(*builder, "string. [\n");
    _if := cast(*Code_If) compiler_get_nodes(intrinsics);
    assert(_if.kind == .IF);
    for _if.then_block.statements {
        _case := cast(*Code_Case) it;
        if _case.kind != .CASE || !_case.condition
            continue;
        literal := cast(*Code_Literal) _case.condition;
        assert(literal.kind == .LITERAL && literal.value_type == .STRING);
        print_to_builder(*builder, "    \"%\",\n", replace(literal._string, "\\", "\\\\"));
    }
    append(*builder, "];");
    return builder_to_string(*builder);
}

get_word :: (word_name: string) -> string, found: bool {
    word := table_find_pointer(*user_words, word_name);
    if word  return word.*, true;

    word = table_find_pointer(*project_words, word_name);
    if word  return word.*, true;

    word = table_find_pointer(*global_words, word_name);
    if word  return word.*, true;

    word = table_find_pointer(*baked_words, word_name);
    if word  return word.*, true;

    return "", false;
}

get_stack :: (stack_name: string) -> *[..] Stack_Item {
    for 0 .. user_stack_count - 1
        if user_stack_names[it] == stack_name
            return *user_stacks[it];

    if user_stack_count >= max_user_stacks  return null; // out of user stacks

    index := user_stack_count;
    user_stack_count += 1;
    user_stack_names[index] = unique_string(stack_name);
    return *user_stacks[index];
}

word_cache : Table(string, bool);

try_handle_action_word :: (word_name: string) -> handled: bool, found: bool {
    action, found := table_find(*action_words, word_name);
    if !found  return false, false;

    if action == .do_nothing
        return true, true;

    handled := handle_common_editor_action(action);
    if !handled
        handled = active_editor_handle_event(Input.Event.{}, action);
    return handled, true;
}

words_for_space :: (space: Space) -> *Table(string, string) {
    if #complete space == {
        case .baked;    return *baked_words;
        case .global;   return *global_words;
        case .project;  return *project_words;
        case .user;     return *user_words;
        case .none;     return null;
    }
}

peek :: (t: type_of(Stack_Item.type), stack: *[..] Stack_Item) -> *Stack_Item #expand {
    if stack.count && stack.*[stack.count - 1].type == t
        return *stack.*[stack.count - 1];
    else
        return null;
}

based_on_string :: (item: Stack_Item) -> bool {
    return item.type == .text || item.type == .word || item.type == .sequence;
}

pop_message :: (item: Stack_Item, stack: *[..] Stack_Item) #expand {
    array_add(*popped_during_this_execute_word, item);
}

push_message :: (item: Stack_Item, stack: *[..] Stack_Item) #expand {
    // @TODO probably remove this entirely
}

push :: (item: Stack_Item, stack: *[..] Stack_Item) {
    push_message(item, stack);
    array_add(stack, item);
}

push :: (value: $T, stack: *[..] Stack_Item) {
    item := stack_item(value);
    push_message(item, stack);
    array_add(stack, item);
}

push_already_unique_string :: (s: string, stack: *[..] Stack_Item) {
    item : Stack_Item = ---;
    item.type = .text;
    item.string_value = s;
    push_message(item, stack);
    array_add(stack, item);
}

push_word :: (word: string, stack: *[..] Stack_Item) {
    item : Stack_Item = ---;
    item.type = .word;
    item.string_value = unique_string(word);
    push_message(item, stack);
    array_add(stack, item);
}

push_error :: (value: s64, stack: *[..] Stack_Item) {
    error : Stack_Item = ---;
    error.type = .error;
    error.int_value = value;
    push_message(error, stack);
    array_add(stack, error);
}

push_type :: (type: type_of(Stack_Item.type), stack: *[..] Stack_Item) {
    item : Stack_Item = ---;
    item.type = .type;
    item.int_value = xx type;
    push_message(item, stack);
    array_add(stack, item);
}

push_separator :: (stack: *[..] Stack_Item) {
    separator : Stack_Item = ---;
    separator.type = .separator;
    push_message(separator, stack);
    array_add(stack, separator);
}

push_empty_sequence :: inline (stack: *[..] Stack_Item) {
    push_sequence("", stack);
}

push_sequence :: (sequence: string, stack: *[..] Stack_Item) {
    item : Stack_Item = ---;
    item.type = .sequence;
    item.string_value = unique_string(sequence);
    push_message(item, stack);
    array_add(stack, item);
}

stack_item :: (value: bool) -> Stack_Item {
    result : Stack_Item = ---;
    result.type = .boolean;
    result.int_value = ifx value then 1 else 0;
    result.value = ifx value then 1.0 else 0.0;
    result.bool_value = value;
    return result;
}

stack_item :: (value: int) -> Stack_Item {
    result : Stack_Item = ---;
    result.type = .int_number;
    result.int_value = value;
    result.value = cast,trunc(float)value;
    return result;
}

stack_item :: (value: float) -> Stack_Item {
    result : Stack_Item = ---;
    result.type = .number;
    result.value = value;
    return result;
}

stack_item :: (value: string) -> Stack_Item {
    result : Stack_Item = ---;
    result.type = .text;
    result.string_value = unique_string(value);
    return result;
}

to_bool :: (item: Stack_Item) -> bool {
    if #complete item.type == {
        case .word;        #through;
        case .text;        #through;
        case .sequence;    return item.string_value != "";

        case .int_number;  return item.int_value != 0;
        case .number;      return item.value != 0;
        case .boolean;     return item.bool_value;
        case .error;       return false;
        case .separator;   return false;
        case .type;        return false;
    }
}

has_string_value :: (item: Stack_Item) -> bool {
    return item.type == .word || item.type == .text || item.type == .sequence;
}

to_string :: (item: Stack_Item) -> string {
    if #complete item.type == {
        case .word;        #through;
        case .text;        #through;
        case .sequence;    return item.string_value;

        case .int_number;  return tprint("%", item.int_value);
        case .number;      return tprint("%", item.value);
        case .boolean;     return tprint("%", item.bool_value);
        case .error;       return tprint("Error: %", item.int_value);
        case .separator;   return ficus_separator_name;

        case .type;
        if #complete cast(type_of(Stack_Item.type))item.int_value == {
            case .word;       return "<word>";
            case .text;       return "<text>";
            case .sequence;   return "<sequence>";
            case .int_number; return "<number>";
            case .number;     return "<number>";
            case .boolean;    return "<boolean>";
            case .error;      return "<error>";
            case .separator;  return "<separator>";
            case .type;       return "<type>";
        }
    }
}

to_display_string :: (item: Stack_Item) -> string {
    if #complete item.type == {
        case .word;        return trim(item.string_value);
        case .text;        return tprint("\"%\"", trim(item.string_value));
        case .sequence;    return tprint("[%]", trim(item.string_value));
        case .int_number;  return tprint("%", item.int_value);
        case .number;      return tprint("%", item.value);
        case .boolean;     return tprint("%", item.bool_value);
        case .error;       return tprint("<Error: %>", item.int_value);
        case .separator;   return ficus_separator_name;

        case .type;
        if #complete cast(type_of(Stack_Item.type))item.int_value == {
            case .word;       return "<word>";
            case .text;       return "<text>";
            case .sequence;   return "<sequence>";
            case .int_number; return "<number>";
            case .number;     return "<number>";
            case .boolean;    return "<boolean>";
            case .error;      return "<error>";
            case .separator;  return "<separator>";
            case .type;       return "<type>";
        }
    }
}

clear_stack :: (stack: *[..] Stack_Item) {
    array_reset(stack);
}

clear_all_stacks :: () {
    clear_stack(*main_stack);
    for * user_stacks
        clear_stack(it);
}


ficus_separator_name :: "\\";