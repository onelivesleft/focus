highlight_fig_syntax :: (using buffer: *Buffer) {
    tokenizer: Tokenizer = ---;
    tokenizer.buf   = to_string(bytes);
    tokenizer.max_t = bytes.data + bytes.count;
    tokenizer.t     = bytes.data;

    highlight_fig_syntax(buffer, *tokenizer, true);
}

highlight_fig_syntax :: (using buffer: *Buffer, start_index: s32, count: s32) {
    tokenizer: Tokenizer = ---;
    tokenizer.buf   = to_string(bytes);
    tokenizer.max_t = bytes.data + start_index + count;
    tokenizer.t     = bytes.data + start_index;

    highlight_fig_syntax(buffer, *tokenizer, false);
}

highlight_fig_syntax :: (using buffer: *Buffer, using tokenizer: *Tokenizer, reset: bool) {
    if reset  reset_buffer_info_arrays(buffer);

    token : Token;
    token.type = .eol;

    while true {
        prev_token = token;
        is_start_of_line = prev_token.type == .eol;

        token = get_next_token(tokenizer);
        //print("%\n", token);

        if token.type == .eof  break;

        /*
        if token.type == .hyperlink {
            color := COLOR_MAP[token.type];
            memset(colors.data + token.start, xx color, token.sublen);
            color = COLOR_MAP[Token.Type.hyperlink_url];
            memset(colors.data + token.start + token.sublen, xx color, token.len - token.sublen);
        }
        */
        color := COLOR_MAP[token.type];
        memset(colors.data + token.start, xx color, token.len);

        if token.type == .string_literal || token.type == .string_error {
            color := ifx token.type == .string_literal then COLOR_MAP[Token.Type.punctuation] else COLOR_MAP[Token.Type.error];
            memset(colors.data + token.start, xx color, token.sublen);
            memset(colors.data + token.start + token.len - token.sublen, xx color, token.sublen);
        }
        else if token.type == .declaration { // `:` guaranteed to be next char in buffer
            token = get_next_token(tokenizer);
            assert(token.type == .word); // solo `:` should be treated as a word, under normal conditions
            if token.len != 1  // junk after `:` on declaration
                token.type = .error;
            else
                token.type = .punctuation;
            color := COLOR_MAP[token.type];
            memset(colors.data + token.start, xx color, token.len);
        }
    }
}

#scope_file

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

        case #char "["; #through;
        case #char "]";
        t += 1;
        token.type = .punctuation;

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
            token.type = .string_error;
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
        token.type = .string_error;
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
        token.type = .string_error;
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
    token.type = .string_error;
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

    Type :: enum u16 {
        eof;
        eol;
        comment;

        error;
        string_error;

        declaration;
        punctuation;
        word;
        number_literal;
        string_literal;
    }

}

// Must match the order of the types in the enum above
COLOR_MAP :: Code_Color.[
    .COMMENT,       // eof - obviously not used
    .COMMENT,       // eol - obviously not used
    .COMMENT,       // comment

    .ERROR,         // error
    .STRING,        // string_error

    .FUNCTION,      // declaration
    .PUNCTUATION,   // punctuation
    .DEFAULT,       // word
    .VALUE,         // number_literal
    .STRING,        // string_literal
];

#run assert(enum_highest_value(Token.Type) == COLOR_MAP.count - 1);
