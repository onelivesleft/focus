FIG__ERROR :: 1;

max_stack_size :: 4096;
max_user_stacks :: 64;
max_instructions_per_frame :: 1024;

#add_context ficus : struct {
    baked_words: Table(string, string);
    global_words: Table(string, string);
    project_words: Table(string, string);
    user_words: Table(string, string);

    frame_index := 0;
    instruction_count := 0;
    main_stack: [..] Stack_Item;
    user_stacks: [max_user_stacks] [..] Stack_Item;
    user_stack_names: [max_user_stacks] string;

    jump_stack: [..] Jump_Target;
    record_jump_target := false;
    jump_to_jump_target := false;

    move_tokens_to_stack_count := 0;

    flags : enum_flags {
        already_opened_project;
        keep_stack;
        displayed_header;
    }

    Jump_Target :: struct {
        target: s64;
        frame_index: s64;
    }
}

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
    }

    string_value: string;

    #place string_value;
    int_value: s64;
    value: float32;
    bool_value: bool;
}

ficus_scripts_to_execute : [..] struct {
    script: string;
    event: string;
    space: Space;
    output: Volume;
};

ficus_events :: string.["on_open"];

Space :: enum { none; baked; global; project; user; }
Volume :: enum { silent; errors; default; verbose; }

action_words : Table(string, Action_Editors);

ficus_pool: Flat_Pool;
ficus_allocator: Allocator;
ficus_string_lookup: Table(string, *u8);

init_ficus :: () {
    ficus_allocator.proc = flat_pool_allocator_proc;
    ficus_allocator.data = *ficus_pool;

    #insert -> string {
        b: String_Builder;
        baked_words, ok := read_entire_file("src/baked_words.fig");
        if !ok  compiler_report("Could not find/read ficus baked words file (src/baked_word.fig)", mode=.WARNING);
        print_to_builder(*b, #string jai
            _execute_string(#string fig
%
            fig, *context.ficus.main_stack, true, .baked, .silent);
        jai, baked_words);
        for name, index: ACTIONS_EDITORS  print_to_builder(*b, "table_set(*action_words, \"!%\", %);\n", name, index);
        return builder_to_string(*b);
    }
}

execute_editor :: (editor: *Editor, buffer: *Buffer, space := Space.user, output := Volume.default, $loc := #caller_location) {
    #assert !ends_with(loc.fully_pathed_filename, "ficus.jai"), "This procedure is an API endpoint for ficus, it should not be used internally";
    s := copy_string(cast(string) buffer.bytes, temp);
    _execute_string(s, *context.ficus.main_stack, true, space, output);
    if context.ficus.main_stack  _execute_word("debug_print_stack", *context.ficus.main_stack, true, space, output);
}

execute_string :: inline (s: string, space := Space.user, output := Volume.default, $loc := #caller_location) -> error: string {
    #assert !ends_with(loc.fully_pathed_filename, "ficus.jai"), "This procedure is an API endpoint for ficus, it should not be used internally";
    return _execute_string(copy_string(s, temp), *context.ficus.main_stack, true, space, output);
}

execute_word :: inline (word_name: string, space := Space.user, output := Volume.default, $loc := #caller_location) -> error: string {
    #assert !ends_with(loc.fully_pathed_filename, "ficus.jai"), "This procedure is an API endpoint for ficus, it should not be used internally";
    return _execute_word(copy_string(word_name, temp), *context.ficus.main_stack, true, space, output);
}

try_execute_word_in_space :: inline (word_name: string, space: Space, output := Volume.default, $loc := #caller_location) -> found: bool, error: string {
    #assert !ends_with(loc.fully_pathed_filename, "ficus.jai"), "This procedure is an API endpoint for ficus, it should not be used internally";
    words := words_for_space(space);
    word := table_find_pointer(words, word_name);
    if word  return true, _execute_string(copy_string(word_name, temp), *context.ficus.main_stack, true, space, output);
    else     return false, "";
}

xxxtry_execute_word :: (word_name: string, space := Space.user, output := Volume.default, $loc := #caller_location) -> found: bool, error: string {
    #assert !ends_with(loc.fully_pathed_filename, "ficus.jai"), "This procedure is an API endpoint for ficus, it should not be used internally";
    word, found := get_word(word_name);
    if found
        return true, _execute_string(word, *context.ficus.main_stack, true, space, output);

    handled, found = try_handle_action_word(word_name);
    if found {
        if handled
            return "", true;
        else
            return true, tprint("Error: Tried to perform action [%] but we failed to handle it.", action);
    }

    if array_find(intrinsic_words, word_name)
        return true, _execute_word(word_name, *context.ficus.main_stack, true, space, output, true);

    return false, "";
}

execute_on_main_thread :: (script: string, $event := "", space := Space.user, output := Volume.default) {
    #assert event == "" || array_find(ficus_events, event);
    array_add(*ficus_scripts_to_execute, .{script, event, space, output});
}

#scope_file

reset_environment :: () {
    using *context.ficus;
    flags = 0;
    record_jump_target = false;
    jump_to_jump_target = false;
    move_tokens_to_stack_count = 0;
    instruction_count = 0;
}

console_log :: (s: string, word := "") {
    using *context.ficus;
    leader := "";
    if !(flags & .displayed_header) {
        print_console_header(tprint("[FICUS] %", frame_time));
        flags |= .displayed_header;
    }
    if word
        print_to_console(tprint("[Ficus (%) %] %\n", main_stack.count, word, s));
    else
        print_to_console(tprint("[Ficus (%)] %\n", main_stack.count, s));
}

_execute_string :: (s: string, stack : *[..] Stack_Item, entry_point: bool, space := Space.user, output := Volume.default) -> error: string {
    using *context.ficus;

    my_frame_index := frame_index;
    frame_index += 1;

    if space == .none  return "";

    ERRORS := output >= .errors;
    DEFAULT := output >= .default;
    VERBOSE := output >= .verbose;

    if entry_point  reset_environment();
    finalize := entry_point;

    words := words_for_space(space);
    token : Ficus_Token;
    token.type = .eol;

    using tokenizer := *Ficus_Tokenizer.{s, s.data + s.count, s.data, s.data, false, false, token};
    sequence_depth := 0;
    sequence_start: s32;
    sequence_is_empty: bool;

    error := "";
    token_string := "";

    while !error {
        prev_token = token;
        is_start_of_line = prev_token.type == .eol;

        token = ficus_get_next_token(tokenizer);
        if token.type == .eof  break;
        if token.type == .eol || token.type == .comment
            continue;

        if record_jump_target {
            if VERBOSE  console_log(tprint("Pushed jump target [%]", token.start));
            record_jump_target = false;
            array_add(*jump_stack, .{token.start, my_frame_index});
        }

        token_as_string :: () -> string #expand {
            result : string = ---;
            result.data = buf.data + token.start;
            result.count = token.len;
            return result;
        }

        token_string = token_as_string();
        assert(xx trim(token_string));


        //if move_tokens_to_stack_count  debug_break();
        if sequence_depth || (token.type != .begin_sequence && move_tokens_to_stack_count) {
            added_token_to_stack := false;
            if !sequence_depth && move_tokens_to_stack_count {
                s : string = ---;
                s.data = buf.data + token.start;
                s.count = token.len;
                push_sequence(s, stack);
                if VERBOSE  console_log(tprint("Pushed sequence [%]", s));
                added_token_to_stack = true;
            }
            else if token.type == {
                case .end_sequence;
                    sequence_depth -= 1;
                    if sequence_depth == 0 {
                        if sequence_is_empty {
                            push_empty_sequence(stack);
                            if VERBOSE  console_log("Pushed sequence [ ]");
                        }
                        else {
                            s : string = ---;
                            s.data = buf.data + sequence_start;
                            s.count = token.start - sequence_start;
                            push_sequence(s, stack);
                            if VERBOSE  console_log(tprint("Pushed sequence [%]", s));
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

            if move_tokens_to_stack_count && added_token_to_stack {
                _execute_word("swap", stack, false, space, output, true);
                move_tokens_to_stack_count -= 1;
                if !move_tokens_to_stack_count
                    _execute_word("execute", stack, space, output, true);
            }

            continue;
        }

        if #complete token.type == {
            case .error;
                error = "Parsing error";
                break;

            case .end_sequence;
                error = "Unexpected ]";
                break;

            case .declaration;
                if token_string {
                    word_name := unique_string(token_string);
                    word, new := find_or_add(words, word_name);

                    token = ficus_get_next_token(tokenizer);
                    assert(token_as_string() == ":");
                    definition_start := t;
                    ficus_skip_to_non_indented(tokenizer);
                    definition_end := t;

                    definition : string = ---;
                    definition.data = definition_start;
                    definition.count = definition_end - definition_start;
                    word.* = unique_string(definition);
                    token.type = .eol;
                    if VERBOSE  console_log(tprint("Added word [%] with text: [%]", word_name, trim(word.*)), word_name);
                }

            case .word; #through;
            case .word_with_stack;
                execute_stack : *[..] Stack_Item = ---;
                word_name : string = ---;
                if token.type == .word_with_stack {
                    stack_name:, word_name = split_into_two(token_string, #char "'");
                    execute_stack = get_stack(stack_name);
                    if !execute_stack {
                        error = "Ran out of user stacks";
                        break;
                    }
                }
                else {
                    word_name = token_string;
                    execute_stack = stack;
                }

                error = _execute_word(word_name, execute_stack, space, output);
                if error  break;

                if jump_to_jump_target {
                    jump_target := peek(jump_stack);
                    if jump_target.frame_index != my_frame_index
                        break;

                    jump_to_jump_target = false;
                    if jump_target.target < 0  || jump_target.target > buf.count
                        error = tprint("Bad jump target: %", jump_target);
                    else
                        t = buf.data + jump_target.target;
                }

            case .string_literal;
                token_string.data += token.sublen;
                token_string.count -= token.sublen * 2;
                token_string = trim_through(token_string, #char "\n");
                push(token_string, stack);

            case .begin_sequence;
                sequence_start = token.start + 1;
                sequence_depth = 1;
                sequence_is_empty = true;

            case .number_literal;
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
        else if finalize && move_tokens_to_stack_count
            error = tprint("Expected % more tokens", move_tokens_to_stack_count);
        else if finalize && jump_to_jump_target
            error = "Couldn't find jump target for jump";
    }

    if ERRORS  if error  console_log(error, token_string);

    if finalize {
        if !(flags & .keep_stack)
            clear_all_stacks();
    }

    return error;
}

_execute_word :: inline (word_name: string, stack: *[..] Stack_Item, space: Space, output: Volume, intrinsic_only := false) -> error: string {
    return _execute_word(word_name, stack, false, space, output, intrinsic_only);
}

_execute_word :: (word_name: string, stack: *[..] Stack_Item, entry_point: bool, space: Space, output: Volume, intrinsic_only := false) -> error: string {
    using *context.ficus;

    instruction_count += 1;
    if instruction_count > max_instructions_per_frame
        return tprint("Exceeded instruction count limit (%)", max_instructions_per_frame);

    ERRORS  := output >= .errors;
    DEFAULT := output >= .default;
    VERBOSE := output >= .verbose;

    if !intrinsic_only {
        word, found := get_word(word_name);
        if found
            return _execute_string(word, stack, entry_point, space, output);

        handled:, found = try_handle_action_word(word_name);
        if found {
            if handled  return "";
            else        return tprint("Error: Tried to perform action [%] but we failed to handle it.", word_name);
        }
    }

    pop :: (t: type_of(Stack_Item.type)) -> Stack_Item #expand {
        if !stack.count  `return tprint("% expected <%> but stack was empty", word_name, t);
        item := pop(stack);
        if item.type != t  `return tprint("% expected <%> but found <%>", word_name, t, item.type);
        return item;
    }

    pop :: () -> Stack_Item #expand {
        if !stack.count  `return tprint("% expected a value but stack was empty", word_name);
        item := pop(stack);
        return item;
    }

    handle_basic_operator :: (int_operator: (int, int)->$T, $U: Type = float, float_operator: (float,float)->U = null) #expand {
        b := pop();
        if b.type != .int_number && b.type != .number && b.type != .boolean
            `return tprint("% only work on numbers", `word_name);
        a := pop();
        if a.type != .int_number && a.type != .number && a.type != .boolean
            `return tprint("% only work on numbers", `word_name);
        both_are_ints := (a.type == .int_number || a.type == .boolean) && (b.type == .int_number || b.type == .boolean);
        if both_are_ints
            push(cast(T)int_operator(a.int_value, b.int_value), stack);
        else if float_operator
            push(cast(U)float_operator(a.value, b.value), stack);
        else
            `return tprint("% does not work on numbers (just on int_numbers)", `word_name);
    }

    peek :: () -> Stack_Item #expand {
        if !stack.count  `return tprint("% expected a value but stack was empty", word_name);
        return stack.*[stack.count - 1];
    }

    last_separator :: () -> index: int, found: bool #expand {
        for < i: stack.count - 1 .. 0
            if stack.*[i].type == .separator
                return i, true;
        return 0, false;
    }

    if word_name == {
        case "true";
            push(true, stack);

        case "false";
            push(false, stack);

        case "+";   handle_basic_operator((x, y) => x+y,  float_operator = (x, y) => x+y);
        case "-";   handle_basic_operator((x, y) => x-y,  float_operator = (x, y) => x-y);
        case "*";   handle_basic_operator((x, y) => x*y,  float_operator = (x, y) => x*y);
        case "/";   handle_basic_operator((x, y) => x/y,  float_operator = (x, y) => x/y);
        case "=";   handle_basic_operator((x, y) => x==y, bool, float_operator = (x, y) => x==y);
        case "<";   handle_basic_operator((x, y) => x<y,  bool, float_operator = (x, y) => x<y);
        case ">";   handle_basic_operator((x, y) => x>y,  bool, float_operator = (x, y) => x>y);
        case "<=";  handle_basic_operator((x, y) => x<=y, bool, float_operator = (x, y) => x<=y);
        case ">=";  handle_basic_operator((x, y) => x>=y, bool, float_operator = (x, y) => x>=y);
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

        case ".";
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
            push(item, stack);

        case "copy";
            item := peek();
            push(item, stack);

        case "swap";
            a := pop();
            b := pop();
            push(a, stack);
            push(b, stack);

        case "jump_target";
            record_jump_target = true;

        case "jump";
            if !jump_stack.count  return tprint("Tried to % but the jump_stack is empty", word_name);
            jump_to_jump_target = true;

        case "pop_jump_target";
            if !jump_stack.count  return tprint("Tried to % but the jump_stack is empty", word_name);
            pop(*jump_stack);

        case "expect_then_execute";
            if stack.count < 2
                return tprint("% needs (word, count) but the stack only has % items", word_name, stack.count);
            count := pop(.int_number).int_value;
            if count < 0 || count >= max_stack_size
                return tprint("Illegal value for %: %", word_name, count);
            move_tokens_to_stack_count = count;

        case "execute";
            item := pop();
            if item.type == .sequence || item.type == .word
                return _execute_string(item.string_value, stack, false, space, output);
            else
                push(item, stack);

        case "execute_if";
            sequence := pop(.sequence);
            error := _execute_word("execute", stack, space, output, true); // execute condition
            if error  return error;
            value := pop();
            if to_bool(value) && sequence.string_value
                return _execute_string(sequence.string_value, stack, false, space, output);

        case "execute_if_else";
            sequence_if_false := pop(.sequence);
            sequence_if_true := pop(.sequence);
            error := _execute_word("execute", stack, space, output, true); // execute condition
            if error  return error;
            value := pop();
            if to_bool(value) {
                if sequence_if_true.string_value
                    return _execute_string(sequence_if_true.string_value, stack, false, space, output);
            }
            else {
                if sequence_if_false.string_value
                    return _execute_string(sequence_if_false.string_value, stack, false, space, output);
            }

        case "keep";
            flags |= .keep_stack;

        case "console_position";
            floating_area_position = xx pop(.int_number).int_value & 0xF;

        case "words";
            table_reset(*word_cache);
            for intrinsic_words  table_set(*word_cache, it, true);
            for baked_words    table_set(*word_cache, it_index, true);
            for global_words     table_set(*word_cache, it_index, true);
            for project_words    table_set(*word_cache, it_index, true);
            for user_words       table_set(*word_cache, it_index, true);
            for action_words     table_set(*word_cache, it_index, true);
            for word_cache       push_word(it_index, stack);

        case "print";
            index, found := last_separator();
            start_index := ifx found then index + 1 else index;
            builder : String_Builder;
            for i: start_index .. stack.count - 1 {
                if DEFAULT {
                    append(*builder, to_display_string(stack.*[i]));
                    append(*builder, " ");
                }
            }
            stack.count = index;

            if DEFAULT  console_log(builder_to_string(*builder), word_name);
            else        reset(*builder);

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

        case "open_project";
            item := pop(.text);
            success: bool;
            if flags & .already_opened_project
                success = false;
            else
                success = open_project(to_string(item));
            push(success, stack);

        case "projects";
            names := get_project_names();
            for names  push(it, stack);

        case "open_file";
            item := pop(.text);
            success := editors_open_file(to_string(item));
            push(success, stack);

        case "open_files";
            opened := 0;
            while stack.count {
                if peek(.separator, stack) {
                    pop();
                    break;
                }
                item := pop(.text);
                success := editors_open_file(to_string(item));
                if success  opened += 1;
            }
            push(opened, stack);

        case;
            return tprint("Could not find word [%]", word_name);
    }

    return "";
}

intrinsic_words :: string.[ // @TODO generate this from above proc
    "true", "false", "+", "-", "*", "/", "&", "^", "|", "=", "<", ">", "0-", "and", "or", "not",
    "pop", "push", "peek", ".", "copy", "swap", "expect_then_execute", "execute", "execute_if", "execute_if_else",
    "jump_target", "jump", "pop_jump_target", "keep",
    "debug_stack", "clear", "words", "open_project", "projects", "open_file",
];

get_word :: (word_name: string) -> string, found: bool {
    using *context.ficus;
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
    using *context.ficus;

    for user_stack_names
        if it == stack_name
            return *user_stacks[it_index];

    for user_stack_names {
        if it == "" {
            user_stack_names[it_index] = unique_string(stack_name);
            return *user_stacks[it_index];
        }
    }

    return null;
}

word_cache : Table(string, bool);

try_handle_action_word :: (word_name: string) -> handled: bool, found: bool {
    action, found := table_find(*action_words, word_name);
    if !found  return false, false;

    if action == .do_nothing
        return true, true;

    handled := handle_common_editor_action(action);
    if !handled
        active_editor_handle_event(Input.Event.{}, action);
    return handled, true;
}

words_for_space :: (space: Space) -> *Table(string, string) {
    if #complete space == {
        case .baked;    return *context.ficus.baked_words;
        case .global;   return *context.ficus.global_words;
        case .project;  return *context.ficus.project_words;
        case .user;     return *context.ficus.user_words;
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

push :: (item: Stack_Item, stack: *[..] Stack_Item) {
    array_add(stack, item);
}

push :: (value: $T, stack: *[..] Stack_Item) {
    array_add(stack, stack_item(value));
}

push_word :: (word: string, stack: *[..] Stack_Item) {
    item : Stack_Item = ---;
    item.type = .word;
    item.string_value = unique_string(word);
    array_add(stack, item);
}

push_error :: (value: s64, stack: *[..] Stack_Item) {
    error : Stack_Item = ---;
    error.type = .error;
    error.int_value = value;
    array_add(stack, error);
}

push_separator :: (stack: *[..] Stack_Item) {
    separator : Stack_Item = ---;
    separator.type = .separator;
    array_add(stack, separator);
}

push_empty_sequence :: inline (stack: *[..] Stack_Item) {
    push_sequence("", stack);
}

push_sequence :: (sequence: string, stack: *[..] Stack_Item) {
    item : Stack_Item = ---;
    item.type = .sequence;
    item.string_value = unique_string(sequence);
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
    }
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
        case .separator;   return ".";
    }
}

to_display_string :: (item: Stack_Item) -> string {
    if #complete item.type == {
        case .word;        return item.string_value;
        case .text;        return tprint("\"%\"", item.string_value);
        case .sequence;    return tprint("[%]", item.string_value);
        case .int_number;  return tprint("%", item.int_value);
        case .number;      return tprint("%", item.value);
        case .boolean;     return tprint("%", item.bool_value);
        case .error;       return tprint("<Error: %>", item.int_value);
        case .separator;   return ".";
    }
}

clear_stack :: (stack: *[..] Stack_Item) {
    array_reset(stack);
}

clear_all_stacks :: () {
    using *context.ficus;
    clear_stack(*main_stack);
    for * user_stacks
        clear_stack(it);
}

unique_string :: (s: string) -> string {
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

