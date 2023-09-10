FIG__ERROR :: 1;

#add_context ficus : struct {
    global_words: Table(string, string);
    project_words: Table(string, string);
    user_words: Table(string, string);

    stack: [..] Stack_Item;
    free_list: [..] Stack_Item;

    flags : enum_flags {
        already_opened_project;
    }
}

Stack_Item :: struct {
    type : enum {
        boolean;
        word;
        int_number;
        number;
        text;
        error;
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

Space :: enum { none; global; project; user; }
Volume :: enum { silent; errors; default; verbose; }

action_words : Table(string, Action_Editors);

init_ficus :: () {
    #insert -> string {
        b: String_Builder;
        for name, index: ACTIONS_EDITORS  print_to_builder(*b, "table_set(*action_words, \"%\", %);\n", name, index);
        return builder_to_string(*b);
    }
}

execute_editor :: (editor: *Editor, buffer: *Buffer, space := Space.user, $output := Volume.default) {
    s := copy_string(cast(string) buffer.bytes, temp);
    _execute_string(s, true, space, output);
    if context.ficus.stack  execute_word("dump", space, output);
}

execute_string :: inline (s: string, space := Space.user, $output := Volume.default) -> error: string {
    return _execute_string(s, true, space, output);
}

execute_word :: inline (word_name: string, space := Space.user, $output := Volume.default) -> error: string {
    return _execute_word(word_name, true, space, output);
}

try_execute_word_in_space :: inline (word_name: string, space: Space, $output := Volume.default) -> found: bool, error: string {
    words := words_for_space(space);
    word := table_find_pointer(words, word_name);
    if word  return true, _execute_string(word_name, true, space, output);
    else     return false, "";
}

try_execute_word :: (word_name: string, space := Space.user, $output := Volume.default) -> found: bool, error: string {
    word, found := get_word(word_name);
    if found
        return true, _execute_string(word, true, space, output);

    handled, found = try_handle_action_word(word_name);
    if found {
        if handled
            return "", true;
        else
            return true, tprint("Error: Tried to perform action [%] but we failed to handle it.", action);
    }

    if array_find(intrinsic_words, word_name)
        return true, _execute_word(word_name, true, space, output, true);

    return false, "";
}

execute_on_main_thread :: (script: string, $event := "", space := Space.user, $output := Volume.default) {
    #assert event == "" || array_find(ficus_events, event);
    array_add(*ficus_scripts_to_execute, .{script, event, space, output});
}

ficus_execute_main_thread_scripts :: () {
    scripts_to_execute_this_frame := ficus_scripts_to_execute.count;
    if scripts_to_execute_this_frame {
        for 0 .. scripts_to_execute_this_frame - 1 {
            exec := ficus_scripts_to_execute[it];
            if #complete exec.output == {
                case .silent;
                    execute_string(exec.script, exec.space, .silent);
                    if exec.event
                        try_execute_word_in_space(exec.event, exec.space, .silent);
                case .errors;
                    execute_string(exec.script, exec.space, .errors);
                    if exec.event
                        try_execute_word_in_space(exec.event, exec.space, .errors);
                case .default;
                    execute_string(exec.script, exec.space, .default);
                    if exec.event
                        try_execute_word_in_space(exec.event, exec.space, .default);
                case .verbose;
                    execute_string(exec.script, exec.space, .verbose);
                    if exec.event
                        try_execute_word_in_space(exec.event, exec.space, .verbose);
            }
            free(exec.script);
        }
        if scripts_to_execute_this_frame == ficus_scripts_to_execute.count {
            array_reset(*ficus_scripts_to_execute);
        }
        else {
            for 1 .. scripts_to_execute_this_frame
                array_ordered_remove_by_index(*ficus_scripts_to_execute, 0);
        }
    }
}

#scope_file

console_log :: (s: string, word := "") {
    using *context.ficus;
    if word
        print_to_console(tprint("[Ficus (%) %] %\n", stack.count, word, s));
    else
        print_to_console(tprint("[Ficus (%)] %\n", stack.count, s));
}

_execute_string :: (s: string, entry_point: bool, space := Space.user, $output := Volume.default) -> error: string {
    if space == .none  return "";

    using *context.ficus;

    ERRORS :: output >= .errors;
    DEFAULT :: output >= .default;
    VERBOSE :: output >= .verbose;

    free_after := entry_point;
    words := words_for_space(space);
    token : Ficus_Token;
    token.type = .eol;
    using tokenizer := *Ficus_Tokenizer.{s, s.data + s.count, s.data, s.data, false, false, token};

    if entry_point {
        flags = 0;
    }

    token_as_string :: () -> string #expand {
        result : string = ---;
        result.data = buf.data + token.start;
        result.count = token.len;
        return result;
    }

    error := "";

    while !error {
        prev_token = token;
        is_start_of_line = prev_token.type == .eol;

        token = ficus_get_next_token(tokenizer);
        if #complete token.type == {
            case .eof;
                break;

            case .error;
                error = "Parsing error";
                break;

            case .end_sequence;
                error = "Unexpected ]";
                break;

            case .declaration;
                if token_as_string() {
                    // Need to take a copy of word name in case we're adding it to the words table
                    word_name := copy_string(token_as_string());
                    should_free_word_name := false;
                    word, new := find_or_add(words, word_name);
                    if !new {
                        if word.count  free(word.data);
                        should_free_word_name = true;
                    }

                    token = ficus_get_next_token(tokenizer);
                    assert(token_as_string() == ":");
                    definition_start := t;
                    skip_to_non_indented(tokenizer);
                    definition_end := t;

                    definition : string = ---;
                    definition.data = definition_start;
                    definition.count = definition_end - definition_start;
                    word.* = copy_string(definition);
                    token.type = .eol;
                    if should_free_word_name  free(word_name);
                    #if VERBOSE  console_log(tprint("Added word [%] with text: [%]", word_name, word.*), word_name);
                }

            case .word;
                error = execute_word(token_as_string(), space, output);

            case .string_literal;
                s := token_as_string();
                s.data += token.sublen;
                s.count -= token.sublen * 2;
                s = trim_through(s, #char "\n");
                push(s);

            case .begin_sequence;

            case .number_literal;
                s := token_as_string();
                if contains(s, #char ".") {
                    int_value, ok := parse_int(*s);
                    assert(ok);
                    push(int_value);
                }
                else {
                    float_value, ok := parse_float(*s);
                    assert(ok);
                    push(float_value);
                }

            case .eol; #through;
            case .comment;
            case .punctuation; // syntax highlight only
            case .string_error; // syntax highlight only
        }
    }

    #if ERRORS  if error  console_log(error, token_as_string());

    if free_after {
        for free_list
            if it.type == .text || it.type == .word
                free(it.string_value);
        array_reset(*free_list);
    }

    return error;
}

_execute_word :: (word_name: string, entry_point: bool, space: Space, $output: Volume, intrinsic_only := false) -> error: string {
    using *context.ficus;

    ERRORS :: output >= .errors;
    DEFAULT :: output >= .default;
    VERBOSE :: output >= .verbose;

    if !intrinsic_only {
        word, found := get_word(word_name);
        if found
            return _execute_string(word, entry_point, space, output);

        handled:, found = try_handle_action_word(word_name);
        if found {
            if handled  return "";
            else        return tprint("Error: Tried to perform action [%] but we failed to handle it.", word_name);
        }
    }

    pop :: (t: type_of(Stack_Item.type)) -> Stack_Item #expand {
        if !stack.count  `return tprint("% expected a % but stack was empty", word_name, t);
        item := pop(*stack);
        array_add(*free_list, item);
        if item.type != t  `return tprint("% expected a % but found a %", word_name, t, item.type);
        return item;
    }

    pop :: () #expand {
        item := pop(*stack);
        array_add(*free_list, item);
    }

    if word_name == {
        case "words";
            table_reset(*word_cache);
            for intrinsic_words  table_set(*word_cache, it, true);
            for global_words     table_set(*word_cache, it_index, true);
            for project_words    table_set(*word_cache, it_index, true);
            for user_words       table_set(*word_cache, it_index, true);
            for action_words     table_set(*word_cache, it_index, true);
            for word_cache       push_word(it_index);

        case "dump";
            #if DEFAULT {
                builder : String_Builder;
                for stack {
                    append(*builder, to_display_string(it));
                    append(*builder, " ");
                }
                console_log(builder_to_string(*builder), word_name);
            }

        case "clear";
            clear_stack();

        case "open_project";
            item := pop(.text);
            success: bool;
            if flags & .already_opened_project
                success = false;
            else
                success = open_project(to_string(item));
            push(success);

        case "projects";
            names := get_project_names();
            for names  push(copy_string(it));

        case "open_file";
            item := pop(.text);
            success := editors_open_file(to_string(item));
            push(success);

        case "open_files";
            opened := 0;
            item := peek(.text);
            while item {
                success := editors_open_file(to_string(item));
                if success  opened += 1;
                pop();
                item = peek(.text);
            }
            push(opened);

        case "+";
        case "-";
        case "*";
        case "/";
        case "&";
        case "^";
        case "|";
        case "=";
        case "<";
        case ">";
        case "0=";
        case "0-";

        case;
            return tprint("Could not find word [%]", word_name);
    }

    return "";
}

intrinsic_words :: string.[ // @TODO generate this from above proc
    "dump", "clear", "words", "open_project", "projects", "open_file",
    "+", "-", "*", "/", "&", "^", "|", "=", "<", ">", "0=", "0-",
];


get_word :: (word_name: string) -> string, found: bool {
    using *context.ficus;
    word := table_find_pointer(*user_words, word_name);
    if word  return word.*, true;

    word = table_find_pointer(*project_words, word_name);
    if word  return word.*, true;

    word = table_find_pointer(*global_words, word_name);
    if word  return word.*, true;

    return "", false;
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
        case .global;   return *context.ficus.global_words;
        case .project;  return *context.ficus.project_words;
        case .user;     return *context.ficus.user_words;
        case .none;     return null;
    }
}

peek :: (t: type_of(Stack_Item.type)) -> *Stack_Item #expand {
    using *context.ficus;
    if stack && stack[stack.count - 1].type == t
        return *stack[stack.count - 1];
    else
        return null;
}

push :: (value: $T) {
    using *context.ficus;
    array_add(*stack, stack_item(value));
}

push_word :: (word: string) {
    using *context.ficus;
    item := stack_item(word);
    item.type = .word;
    array_add(*stack, item);
}

push_error :: (value: s64) {
    using *context.ficus;
    error : Stack_Item = ---;
    error.type = .error;
    error.int_value = value;
    array_add(*stack, error);
}

stack_item :: (value: bool) -> Stack_Item {
    result : Stack_Item = ---;
    result.type = .boolean;
    result.bool_value = value;
    return result;
}

stack_item :: (value: s64) -> Stack_Item {
    result : Stack_Item = ---;
    result.type = .int_number;
    result.int_value = value;
    result.value = cast,trunc(float)value;
    return result;
}

stack_item :: (value: float32) -> Stack_Item {
    result : Stack_Item = ---;
    result.type = .number;
    result.value = value;
    return result;
}

stack_item :: (value: string) -> Stack_Item {
    result : Stack_Item = ---;
    result.type = .text;
    result.string_value = copy_string(value);
    return result;
}

to_string :: (item: Stack_Item) -> string {
    if #complete item.type == {
        case .word;        return copy_string(item.string_value, temp);
        case .text;        return copy_string(item.string_value, temp);
        case .int_number;  return tprint("%", item.int_value);
        case .number;      return tprint("%", item.value);
        case .boolean;     return tprint("%", item.bool_value);
        case .error;       return tprint("Error: %", item.int_value);
    }
}

to_display_string :: (item: Stack_Item) -> string {
    if #complete item.type == {
        case .word;        return copy_string(item.string_value, temp);
        case .text;        return tprint("\"%\"", item.string_value);
        case .int_number;  return tprint("%", item.int_value);
        case .number;      return tprint("%", item.value);
        case .boolean;     return tprint("%", item.bool_value);
        case .error;       return tprint("<Error: %>", item.int_value);
    }
}

clear_stack :: () {
    using *context.ficus;
    for * stack {
        if it.type == .text || it.type == .word
            free(it.string_value);
    }
    array_reset(*stack);
}

#scope_export

Ficus_Tokenizer :: struct {
    buf: string;
    max_t:   *u8;
    start_t: *u8;  // cursor when starting parsing new token
    t:       *u8;  // cursor

    syntax_highlight_mode: bool;
    is_start_of_line: bool;


    prev_token : Ficus_Token;
}

Ficus_Token :: struct {
    start, len: s32;
    type: Type;
    sublen: s32;
    stack_item: Stack_Item;
    is_multiline: bool;

    Type :: enum u16 {
        eof;
        eol;
        comment;

        error;
        string_error;

        declaration;
        punctuation;
        begin_sequence;
        end_sequence;
        word;
        number_literal;
        string_literal;
    }
}

ficus_get_next_token :: (using tokenizer: *Ficus_Tokenizer) -> Ficus_Token {
    token: Ficus_Token;
    token.start = cast(s32) (t - buf.data);
    token.type  = .eof;
    if t >= max_t  return token;

    if is_whitespace(t.*) {
        is_start_of_line = false;
        eat_whitespace(tokenizer);
    }

    start_t = t;
    was_start_of_line := is_start_of_line;

    if t.* == #char "\n" {
        token.type = .eol;
        t += 1;
    }
    else if t.* == {
        case #char "#";
        ficus_parse_line_comment(tokenizer, *token);

        case #char "(";
        ficus_parse_block_comment(tokenizer, *token);

        case #char "[";
        token.type = ifx !syntax_highlight_mode then .begin_sequence else .punctuation;
        t += 1;

        case #char "]";
        token.type = ifx !syntax_highlight_mode then .end_sequence else .punctuation;
        t += 1;

        case #char "\"";
        ficus_parse_string(tokenizer, *token);

        case #char "0"; #through;
        case #char "1"; #through;
        case #char "2"; #through;
        case #char "3"; #through;
        case #char "4"; #through;
        case #char "5"; #through;
        case #char "6"; #through;
        case #char "7"; #through;
        case #char "8"; #through;
        case #char "9"; #through;
        case #char "."; #through;
        case #char "-"; #through;
        case #char "+";
        ficus_parse_number(tokenizer, *token);

        case #char ":"; // word starting with :
        t -= 1;
        ficus_parse_word(tokenizer, *token);

        case;
        if was_start_of_line {
            ficus_parse_maybe_declaration(tokenizer, *token);
            if t < max_t && t.* == #char ":"
                token.type = .declaration;
        }
        else {
            ficus_parse_word(tokenizer, *token);
        }
    }

    if t >= max_t then t = max_t;
    token.start = cast(s32) (start_t - buf.data);
    token.len = cast(s32) (t - start_t);

    return token;
}

ficus_is_reserved :: (c: u8) -> bool {
    return c == #char "[" || c == #char "]"
        || c == #char "#" || c == #char "(" || c == #char ")"
        || c == #char "\"";
}

ficus_parse_word :: (using tokenizer: *Ficus_Tokenizer, token: *Ficus_Token) {
    t += 1;
    while t < max_t && t.* != #char "\n" && !is_whitespace(t.*) && !ficus_is_reserved(t.*)
        t += 1;

    token.type = .word;
    return;
}

ficus_parse_maybe_declaration :: (using tokenizer: *Ficus_Tokenizer, token: *Ficus_Token) {
    t += 1;
    while t < max_t && t.* != #char "\n" && !is_whitespace(t.*) && t.* != #char ":" && !ficus_is_reserved(t.*)
        t += 1;

    token.type = .word;
    return;
}

ficus_parse_line_comment :: (using tokenizer: *Ficus_Tokenizer, token: *Ficus_Token) {
    token.type = .comment;
    eat_until_newline(tokenizer);
}

ficus_parse_block_comment :: (using tokenizer: *Ficus_Tokenizer, token: *Ficus_Token) {
    token.type = .comment;
    depth := 1;
    t += 1;
    while t < max_t && depth {
        if t.* == #char "("
            depth += 1;
        else if t.* == #char ")"
            depth -= 1;
        t += 1;
    }
}


ficus_parse_string :: (using tokenizer: *Ficus_Tokenizer, token: *Ficus_Token) {
    token.type = .string_literal;
    sentinel_start := t;
    token.sublen = 1;
    found_whitespace := false;
    cant_be_multiline := false;

    t += 1;
    while t < max_t && t.* != #char "\n" && t.* != #char "\"" {
        if ficus_is_reserved(t.*)
            cant_be_multiline = true;

        if is_whitespace(t.*)
            found_whitespace = true;
        else if found_whitespace
            cant_be_multiline = true;

        t += 1;
    }

    if t >= max_t || t.* == #char "\n" {
        if cant_be_multiline {
            token.type = ifx !syntax_highlight_mode then .error else .string_error;
            return;
        }
    }
    else if t.* == #char "\"" {
        t += 1;
        return;
    }

    token.is_multiline = true;
    t = sentinel_start + 1;
    while t < max_t && t.* != #char "\n" && !is_whitespace(t.*) && !ficus_is_reserved(t.*)
        t += 1;
    token.sublen = xx (t - sentinel_start);
    sentinel : string = ---;
    sentinel.data = sentinel_start;
    sentinel.count = token.sublen;

    while t < max_t && is_whitespace(t.*)
        t += 1;
    if t >= max_t {
        token.type = ifx !syntax_highlight_mode then .error else .string_error;
        return;
    }

    assert(t.* == #char "\n");
    t += 1;

    // at start of multiline string
    indent := 0;
    found_a_line := false;
    line_start := t;
    while t < max_t {
        if !is_whitespace(t.*) {
            if t.* == #char "\n" {
                t += 1;
                line_start = t;
                continue;
            }
            else {
                indent = t - line_start;
                break;
            }
        }
        t += 1;
    }
    if indent == 0 {
        token.type = ifx !syntax_highlight_mode then .error else .string_error;
        return;
    }
    s : string = ---;
    s.count = token.sublen;
    while t + token.sublen <= max_t  {
        s.data = t;
        if s == sentinel {
            t += token.sublen;
            return;
        }
        else if is_whitespace(t.*) {
            t += 1;
        }
        else if t.* == #char "\n" {
            t += 1;
            line_start = t;
        }
        else if t - line_start < indent {
            token.type = .error;
            return;
        }
        else {
            t += 1;
        }
    }
    t += token.sublen;
    token.type = ifx !syntax_highlight_mode then .error else .string_error;
}

ficus_parse_number :: (using tokenizer: *Ficus_Tokenizer, token: *Ficus_Token) {
    if t.* == #char "-" || t.* == #char "+" {
        t += 1;
        if t >= max_t || (t.* < #char "0" || t.* > #char "9") && t.* != #char "." {
            t = start_t;
            ficus_parse_word(tokenizer, token);
            return;
        }
    }

    token.type = .number_literal;
    has_period := t.* == #char ".";
    t += 1;

    while t < max_t && !is_whitespace(t.*) && t.* != #char "\n" {
        if t.* == #char "." {
            if has_period {
                token.type = .error;
                t += 1;
                return;
            }
            else {
                has_period = true;
            }
        }
        else if t.* < #char "0" || t.* > #char "9" {
            token.type = .error;
            t += 1;
            return;
        }
        t += 1;
    }
}

#scope_file

skip_to_non_indented :: (using tokenizer: *Ficus_Tokenizer) {
    prev_was_newline := false;
    while t < max_t {
        if t.* == #char "\n"
            prev_was_newline = true;
        else if prev_was_newline && !is_whitespace(t.*)
            return;
        else
            prev_was_newline = false;
        t += 1;
    }
}

eat_until_newline :: (using tokenizer: *Ficus_Tokenizer) {
    while t < max_t && t.* != #char "\n" {
        t += 1;
    }
}

is_whitespace :: inline (char: u8) -> bool {
    return char == #char " " || char == #char "\t" || char == #char "\r";
}

eat_whitespace :: (using tokenizer: *Ficus_Tokenizer) -> s32 {
    count : s32 = 0;
    while t < max_t && is_whitespace(t.*) {
        count += 1;
        t += 1;
    }
    return count;
}

