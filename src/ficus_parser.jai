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
        word_with_stack;
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
        case #char "\0";
        token.type = .eof;

        case #char "'";
        token.type = .error;
        t += 1;

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

        case;
        if was_start_of_line {
            ficus_parse_maybe_declaration(tokenizer, *token);
            if token.type != .error && t < max_t && t.* == #char ":"
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
    has_stack := false;
    while t < max_t && t.* != #char "\n" && !is_whitespace(t.*) && !ficus_is_reserved(t.*) {
        if t.* == #char "'" {
            if has_stack {
                token.type = .error;
                return;
            }
            else {
                has_stack = true;
                token.sublen = xx (t - start_t);
            }
        }
        t += 1;
    }

    token.type = ifx has_stack then .word_with_stack else .word;
    return;
}

ficus_parse_maybe_declaration :: (using tokenizer: *Ficus_Tokenizer, token: *Ficus_Token) {
    token.type = .word;
    t += 1;
    while t < max_t && t.* != #char "\n" && !is_whitespace(t.*) && t.* != #char ":" && !ficus_is_reserved(t.*) {
        if t.* == #char "'"  token.type = .error;
        t += 1;
    }

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
    has_period := false;
    if t.* == #char "-" || t.* == #char "+" {
        t += 1;
        if t >= max_t || (t.* < #char "0" || t.* > #char "9") && t.* != #char "." {
            t = start_t;
            ficus_parse_word(tokenizer, token);
            return;
        }
    }
    if t.* == #char "." {
        has_period = true;
        t += 1;
        if t >= max_t || (t.* < #char "0" || t.* > #char "9") {
            t = start_t;
            ficus_parse_word(tokenizer, token);
            return;
        }
    }

    token.type = .number_literal;
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
            if !(ficus_is_reserved(t.*) && t.* != #char "\"") {
                token.type = .error;
                t += 1;
            }
            return;
        }
        t += 1;
    }
}


ficus_skip_to_non_indented :: (using tokenizer: *Ficus_Tokenizer) {
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

#scope_file

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

