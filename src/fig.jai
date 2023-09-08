FIG_COULD_NOT_PARSE_NUMBER_ERROR :: 1;

#add_context fig : struct {
    global_words: Table(string, string);
    project_words: Table(string, string);
    user_words: Table(string, string);

    stack: [..] Stack_Item;
    free_list: [..] Stack_Item;
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

fig_startup_script := "";

Space :: enum { none; global; project; user; }
Volume :: enum { silent; errors; default; verbose; }

execute_editor :: (editor: *Editor, buffer: *Buffer, space := Space.user, $output := Volume.default) {
    s := copy_string(cast(string) buffer.bytes, temp);
    _execute_string(s, true, space, output);
    if context.fig.stack  execute_word("dump", space, output);
}

execute_string :: inline (s: string, space := Space.user, $output := Volume.default) -> error: string {
    return _execute_string(s, true, space, output);
}

#scope_file

console_log :: (s: string) { print_to_console(s, append_newline = true); }

_execute_string :: inline (s: string, space := Space.user, $output := Volume.default) -> error: string {
    return _execute_string(s, false, space, output);
}

_execute_string :: (s: string, free_after: bool, space := Space.user, $output := Volume.default) -> error: string {
    if space == .none  return "";

    using *context.fig;

    ERRORS :: output >= .errors;
    DEFAULT :: output >= .default;
    VERBOSE :: output >= .verbose;

    #if DEFAULT  console_log(tprint("\nFig [%]", frame_time));

    words := words_for_space(space);
    token : Token;
    token.type = .eol;
    using tokenizer := *Tokenizer.{s, s.data + s.count, s.data, s.data, false, token};

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

        token = get_next_token(tokenizer);
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
                word_name := token_as_string();
                word, new := find_or_add(words, word_name);
                if !new && word.count  free(word.data);

                token = get_next_token(tokenizer);
                assert(token_as_string() == ":");
                definition_start := t;
                skip_to_non_indented(tokenizer);
                definition_end := t;

                definition : string = ---;
                definition.data = definition_start;
                definition.count = definition_end - definition_start;
                word.* = copy_string(definition);
                token.type = .eol;
                #if VERBOSE  console_log(tprint("Added word [%] with text: [%]", word_name, word.*));

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
            s_int := token_as_string();
            s_float := s_int;
            int_value, ok := parse_int(*s_int);
            if ok {
                push(int_value);
            }
            else {
                float_value:, ok = parse_float(*s_float);
                if ok  push(int_value);
                else   push_error(FIG_COULD_NOT_PARSE_NUMBER_ERROR);
            }

            case .eol; #through;
            case .comment;
        }
    }

    #if ERRORS  if error  console_log(error);

    if free_after {
        for free_list
            if it.type == .text || it.type == .word
                free(it.string_value);
        array_reset(*free_list);
    }
    return error;
}

#scope_export

word_cache : Table(string, bool);

execute_word :: (word_name: string, space: Space, $output: Volume) -> error: string {
    using *context.fig;

    ERRORS :: output >= .errors;
    DEFAULT :: output >= .default;
    VERBOSE :: output >= .verbose;

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
            for word_cache       push(it_index);

        case "dump";
            builder : String_Builder;
            print_to_builder(*builder, "\n% items:\n", stack.count);
            for stack {
                append(*builder, to_string(it));
                append(*builder, " ");
            }
            append(*builder, "\n");
            #if DEFAULT  console_log(builder_to_string(*builder));

        case "clear";
            clear_stack();

        case "open_project";
            item := pop(.text);
            success := open_project(to_string(item));
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

        case;
            word := table_find_pointer(*user_words, word_name);
            if !word  word = table_find_pointer(*project_words, word_name);
            if !word  word = table_find_pointer(*global_words, word_name);
            if !word  return tprint("Could not find word [%]", word_name);
            _execute_string(word.*, space, output);

    }

    return "";
}


intrinsic_words :: string.[ // @TODO generate this from above proc
    "dump", "clear", "words", "open_project", "projects", "open_file"
];

#scope_file

words_for_space :: (space: Space) -> *Table(string, string) {
    if #complete space == {
        case .global;   return *context.fig.global_words;
        case .project;  return *context.fig.project_words;
        case .user;     return *context.fig.user_words;
        case .none;     return null;
    }
}

peek :: (t: type_of(Stack_Item.type)) -> *Stack_Item #expand {
    using *context.fig;
    if stack && stack[stack.count - 1].type == t
        return *stack[stack.count - 1];
    else
        return null;
}

push :: (value: $T) {
    using *context.fig;
    array_add(*stack, stack_item(value));
}

push_error :: (value: s64) {
    using *context.fig;
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


clear_stack :: () {
    using *context.fig;
    for * stack {
        if it.type == .text || it.type == .word
            free(it.string_value);
    }
    array_reset(*stack);
}


get_next_token :: (using tokenizer: *Tokenizer) -> Token {
    token: Token;
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
        parse_line_comment(tokenizer, *token);

        case #char "(";
        parse_block_comment(tokenizer, *token);

        case #char "[";
        token.type = .begin_sequence;
        t += 1;

        case #char "]";
        token.type = .end_sequence;
        t += 1;

        case #char "\"";
        parse_string(tokenizer, *token);

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
        parse_number(tokenizer, *token);

        case #char ":"; // word starting with :
        t -= 1;
        parse_word(tokenizer, *token);

        case;
        if was_start_of_line {
            parse_maybe_declaration(tokenizer, *token);
            if t < max_t && t.* == #char ":"
                token.type = .declaration;
        }
        else {
            parse_word(tokenizer, *token);
        }
    }

    if t >= max_t then t = max_t;
    token.start = cast(s32) (start_t - buf.data);
    token.len = cast(s32) (t - start_t);

    return token;
}

is_reserved :: (c: u8) -> bool {
    return c == #char "[" || c == #char "]"
        || c == #char "#" || c == #char "(" || c == #char ")"
        || c == #char "\"";
}

parse_word :: (using tokenizer: *Tokenizer, token: *Token) {
    t += 1;
    while t < max_t && t.* != #char "\n" && !is_whitespace(t.*) && !is_reserved(t.*)
        t += 1;

    token.type = .word;
    return;
}

parse_maybe_declaration :: (using tokenizer: *Tokenizer, token: *Token) {
    t += 1;
    while t < max_t && t.* != #char "\n" && !is_whitespace(t.*) && t.* != #char ":" && !is_reserved(t.*)
        t += 1;

    token.type = .word;
    return;
}

parse_line_comment :: (using tokenizer: *Tokenizer, token: *Token) {
    token.type = .comment;
    eat_until_newline(tokenizer);
}

parse_block_comment :: (using tokenizer: *Tokenizer, token: *Token) {
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


parse_string :: (using tokenizer: *Tokenizer, token: *Token) {
    token.type = .string_literal;
    sentinel_start := t;
    token.sublen = 1;
    found_whitespace := false;
    cant_be_multiline := false;

    t += 1;
    while t < max_t && t.* != #char "\n" && t.* != #char "\"" {
        if is_reserved(t.*)
            cant_be_multiline = true;

        if is_whitespace(t.*)
            found_whitespace = true;
        else if found_whitespace
            cant_be_multiline = true;

        t += 1;
    }

    if t >= max_t || t.* == #char "\n" {
        if cant_be_multiline {
            token.type = .error;
            return;
        }
    }
    else if t.* == #char "\"" {
        t += 1;
        return;
    }

    t = sentinel_start + 1;
    while t < max_t && t.* != #char "\n" && !is_whitespace(t.*) && !is_reserved(t.*)
        t += 1;
    token.sublen = xx (t - sentinel_start);
    sentinel : string = ---;
    sentinel.data = sentinel_start;
    sentinel.count = token.sublen;

    while t < max_t && is_whitespace(t.*)
        t += 1;
    if t >= max_t {
        token.type = .error;
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
        token.type = .error;
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
    token.type = .error;
}

parse_number :: (using tokenizer: *Tokenizer, token: *Token) {
    if t.* == #char "-" || t.* == #char "+" {
        t += 1;
        if t >= max_t || (t.* < #char "0" || t.* > #char "9") && t.* != #char "." {
            t = start_t;
            parse_word(tokenizer, token);
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

skip_to_non_indented :: (using tokenizer: *Tokenizer) {
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

eat_until_newline :: (using tokenizer: *Tokenizer) {
    while t < max_t && t.* != #char "\n" {
        t += 1;
    }
}

is_whitespace :: inline (char: u8) -> bool {
    return char == #char " " || char == #char "\t" || char == #char "\r";
}

eat_whitespace :: (using tokenizer: *Tokenizer) -> s32 {
    count : s32 = 0;
    while t < max_t && is_whitespace(t.*) {
        count += 1;
        t += 1;
    }
    return count;
}


Tokenizer :: struct {
    buf: string;
    max_t:   *u8;
    start_t: *u8;  // cursor when starting parsing new token
    t:       *u8;  // cursor

    is_start_of_line: bool;

    prev_token : Token;
}

Token :: struct {
    start, len: s32;
    type: Type;
    sublen: s32;
    stack_item: Stack_Item;

    Type :: enum u16 {
        eof;
        eol;
        comment;

        error;

        declaration;
        begin_sequence;
        end_sequence;
        word;
        number_literal;
        string_literal;
    }
}
