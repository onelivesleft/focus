highlight_md_syntax :: (using buffer: *Buffer) {
    tokenizer: Tokenizer = ---;
    tokenizer.buf   = to_string(bytes);
    tokenizer.max_t = bytes.data + bytes.count;
    tokenizer.t     = bytes.data;
    highlight_md_syntax(buffer, *tokenizer, true);
}

highlight_md_syntax :: (using buffer: *Buffer, start_index: s32, count: s32) {
    tokenizer: Tokenizer = ---;
    tokenizer.buf   = to_string(bytes);
    tokenizer.max_t = bytes.data + start_index + count;
    tokenizer.t     = bytes.data + start_index;

    highlight_md_syntax(buffer, *tokenizer, false);
}

highlight_md_syntax :: (using buffer: *Buffer, using tokenizer: *Tokenizer, reset_regions: bool) {
    if reset_regions  reset_buffer_regions(buffer);

    blockquotes : [64] s32;
    blockquote_index := 0;

    token : Token;
    token.type = .eol;

    while true {
        prev_token = token;
        if prev_token.type == .eol
            indent = eat_white_space(tokenizer);
        else
            indent = 0;

        is_start_of_line = prev_token.type == .eol || prev_token.type == .blockquote;

        token = get_next_token(tokenizer);
        //print("%\n", token);

        if token.type == .eof  break;

        if token.type == .blockquote || (blockquote_index > 0 && prev_token.type == .eol) {
            new_level := ifx token.type == .blockquote then token.sublen else 0;
            while blockquote_index < new_level && blockquote_index < blockquotes.count - 1 {
                blockquotes[blockquote_index] = token.start;
                blockquote_index += 1;
            }
            while blockquote_index > new_level && blockquote_index > 0 {
                blockquote_index -= 1;
                end := ifx token.type == .blockquote then token.start else prev_token.start;
                add_buffer_region(buffer, blockquotes[blockquote_index], end, true, 1);
            }
        }

        if token.type == .hyperlink {
            color := COLOR_MAP[token.type];
            memset(colors.data + token.start, xx color, token.sublen);
            color = COLOR_MAP[Token.Type.hyperlink_url];
            memset(colors.data + token.start + token.sublen, xx color, token.len - token.sublen);
        }
        else {
            color := COLOR_MAP[token.type];
            memset(colors.data + token.start, xx color, token.len);
        }

        if token.type == .codeblock {
            identifier := substring(buf, token.start + 3, token.sublen);
            maybe_highlight_inner_language(buffer, language_from_extension(identifier), token.start + 3 + token.sublen, token.len - 6 - token.sublen, false);
            add_buffer_region(buffer, token.start, token.start + token.len, false, 1);
        }
    }

    while blockquote_index > 0 {
        blockquote_index -= 1;
        end := ifx token.type == .blockquote then token.start else prev_token.start;
        add_buffer_region(buffer, blockquotes[blockquote_index], end, true, 1);
    }
}

#scope_file

get_next_token :: (using tokenizer: *Tokenizer) -> Token {
    token: Token;
    token.start = cast(s32) (t - buf.data);
    token.type  = .eof;
    if t >= max_t  return token;

    start_t = t;

    // @TODO \

    if t.* == #char "\n" {
        token.type = .eol;
        t += 1;
    }
    else if is_start_of_line {
        if t.* == {
            case #char "#";
            parse_header(tokenizer, *token);

            case #char ">";
            parse_blockquote(tokenizer, *token);

            case #char "`";
            parse_codeblock(tokenizer, *token);

            case #char "0"; #through;
            case #char "1"; #through;
            case #char "2"; #through;
            case #char "3"; #through;
            case #char "4"; #through;
            case #char "5"; #through;
            case #char "6"; #through;
            case #char "7"; #through;
            case #char "8"; #through;
            case #char "9";
            parse_ordered_list(tokenizer, *token);

            case #char "-"; #through;
            case #char "*"; #through;
            case #char "+";
            parse_unordered_list(tokenizer, *token);

            case #char "[";
            parse_hyperlink(tokenizer, *token);

            case;
            parse_default(tokenizer, *token);
        }
    }
    else {
        eat_white_space(tokenizer);

        start_t = t;
        token.start = cast(s32) (t - buf.data);

        if t.* == {
            case #char "`";
            parse_code(tokenizer, *token);

            case #char "[";
            parse_hyperlink(tokenizer, *token);

            case;
            parse_default(tokenizer, *token);
        }
    }

    if t >= max_t then t = max_t;
    token.len = cast(s32) (t - start_t);

    return token;
}

parse_default :: (using tokenizer: *Tokenizer, token: *Token) {
    t += 1;
    while t < max_t && t.* != #char "\n" && !is_whitespace(t.*) && t.* != #char "`" && t.* != #char "["
        t += 1;

    token.type = .default;
    return;
}

parse_hyperlink :: (using tokenizer: *Tokenizer, token: *Token) {
    t += 1;
    while t < max_t && t.* != #char "]" {
        if t.* == #char "\n" {
            token.type = .default;
            return;
        }
        t += 1;
    }

    t += 1;
    if t.* != #char "(" {
        token.type = .default;
        return;
    }

    end_of_text := t;

    t += 1;
    while t < max_t && t.* != #char ")" {
        if t.* == #char "\n" {
            token.type = .default;
            return;
        }
        t += 1;
    }

    if t.* != #char ")" {
        token.type = .default;
        return;
    }

    token.type = .hyperlink;
    token.sublen = xx (end_of_text - start_t);
    t += 1;
}

parse_code :: (using tokenizer: *Tokenizer, token: *Token) {
    t += 1;
    while t < max_t && t.* != #char "`" {
        if t.* == #char "\n" {
            token.type = .error;
            return;
        }
        t += 1;
    }

    token.type = .code;
    t += 1;
    return;
}

parse_header :: (using tokenizer: *Tokenizer, token: *Token) {
    t += 1;
    header_level := 1;
    while t < max_t && t.* == #char "#" && header_level < 6 {
        header_level += 1;
        t += 1;
    }

    if <<t != #char " " {
        token.type = .error;
    }
    else if header_level == {
        case 1; token.type = .header1;
        case 2; token.type = .header2;
        case 3; token.type = .header3;
        case 4; token.type = .header4;
        case 5; token.type = .header5;
        case 6; token.type = .header6;
    }

    eat_until_newline(tokenizer);
}

parse_blockquote :: (using tokenizer: *Tokenizer, token: *Token) {
    t += 1;
    blockquote_level : s32 = 1;
    while t < max_t && t.* == #char ">" {
        blockquote_level += 1;
        t += 1;
    }

    if !is_whitespace(t.*) && t.* != #char "\n" {
        token.type = .error;
        eat_until_newline(tokenizer);
    }
    else {
        token.type = .blockquote;
        token.sublen = blockquote_level;
        t += 1;
    }
}

parse_codeblock :: (using tokenizer: *Tokenizer, token: *Token) {
    t += 1;
    backticks := 1;
    while t < max_t && t.* == #char "`" && backticks < 3 {
        backticks += 1;
        t += 1;
    }

    if backticks == 4 {
        token.type = .error;
        eat_until_newline(tokenizer);
        return;
    }

    if backticks < 3 {
        t = start_t;
        parse_code(tokenizer, token);
        return;
    }

    terminator :: "\n```";
    end := find_index_from_left(buf, terminator, start_index = t - buf.data);
    if end < 0 {
        t = max_t;
        token.type = .error;
        return;
    }

    token.sublen = 0;
    while t < max_t && !is_whitespace(t.*) && t.* != #char "\n" {
        t += 1;
        token.sublen += 1;
    }

    t = buf.data + end + terminator.count;
    token.type = .codeblock;
}

parse_ordered_list :: (using tokenizer: *Tokenizer, token: *Token) {
    t += 1;
    while t < max_t && t.* >= #char "0" && t.* <= #char "9"
        t += 1;

    if t == max_t || t.* != #char "." {
        parse_default(tokenizer, token);
        return;
    }

    t += 1;
    if t == max_t {
        parse_default(tokenizer, token);
        return;
    }

    if is_whitespace(t.*) && indent % 4 == 0
        token.type = .ordered_list;
    else
        token.type = .error;

    eat_until_newline(tokenizer);
    return;
}

parse_unordered_list :: (using tokenizer: *Tokenizer, token: *Token) {
    t += 1;
    if t == max_t || !is_whitespace(t.*) {
        parse_default(tokenizer, token);
        return;
    }

    if indent % 4 == 0  token.type = .unordered_list;
    else                token.type = .error;

    eat_until_newline(tokenizer);
    return;
}

eat_until_newline :: (using tokenizer: *Tokenizer) {
    while t < max_t && t.* != #char "\n" {
        t += 1;
    }
}

is_whitespace :: inline (char: u8) -> bool {
    return char == #char " " || char == #char "\t" || char == #char "\r";
}

eat_white_space :: (using tokenizer: *Tokenizer) -> s32 {
    count : s32 = 0;
    while t < max_t && is_whitespace(<< t) {
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
    indent : s32 = 0;

    prev_token : Token;
}

Token :: struct {
    start, len: s32;
    type: Type;
    sublen: s32;

    Type :: enum u16 {
        eof;
        eol;
        blockquote;

        error;
        default;

        header1;
        header2;
        header3;
        header4;
        header5;
        header6;

        ordered_list;
        unordered_list;

        code;
        codeblock;

        hyperlink;
        hyperlink_url;
    }

}

// Must match the order of the types in the enum above
COLOR_MAP :: Code_Color.[
    .COMMENT,       // eof - obviously not used
    .COMMENT,       // eol - obviously not used
    .COMMENT,       // blockquote - not colored directly; turned into a region

    .ERROR,         // error
    .DEFAULT,       // default

    .DIRECTIVE,     // header1
    .JUMP_KEYWORD,  // header2
    .VALUE_KEYWORD, // header3
    .KEYWORD,       // header4
    .KEYWORD,       // header5
    .KEYWORD,       // header6

    .OPERATION,     // ordered_list
    .FUNCTION,      // unorderer_list

    .STRING,        // code
    .STRING,        // codeblock

    .STRING,        // hyperlink
    .VALUE_KEYWORD, // hyperlink url
];

#run assert(enum_highest_value(Token.Type) == COLOR_MAP.count - 1);