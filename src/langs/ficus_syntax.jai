highlight_ficus_syntax :: (using buffer: *Buffer) {
    tokenizer: Ficus_Tokenizer = ---;
    tokenizer.buf   = to_string(bytes);
    tokenizer.max_t = bytes.data + bytes.count;
    tokenizer.t     = bytes.data;
    tokenizer.syntax_highlight_mode = true;

    highlight_ficus_syntax(buffer, *tokenizer, true);
}

highlight_ficus_syntax :: (using buffer: *Buffer, start_index: s32, count: s32) {
    tokenizer: Ficus_Tokenizer = ---;
    tokenizer.buf   = to_string(bytes);
    tokenizer.max_t = bytes.data + start_index + count;
    tokenizer.t     = bytes.data + start_index;
    tokenizer.syntax_highlight_mode = true;

    highlight_ficus_syntax(buffer, *tokenizer, false);
}

highlight_ficus_syntax :: (using buffer: *Buffer, using tokenizer: *Ficus_Tokenizer, reset: bool) {
    if_reset_then_generate_buffer_info_arrays();

    token : Ficus_Token;
    token.type = .eol;

    while true {
        prev_token = token;
        is_start_of_line = prev_token.type == .eol;

        token = ficus_get_next_token(tokenizer);
        //print("%\n", token);

        if token.type == .eof  break;

        /*
        if token.type == .hyperlink {
            color := COLOR_MAP[token.type];
            memset(colors.data + token.start, xx color, token.sublen);
            color = COLOR_MAP[Ficus_Token.Type.hyperlink_url];
            memset(colors.data + token.start + token.sublen, xx color, token.len - token.sublen);
        }
        */

        if token.type == .declaration
            add_buffer_section(buffer, token.start, false);

        color := COLOR_MAP[token.type];
        if token.type == .string_literal || token.type == .string_error {
            if token.type == .string_error || !token.is_multiline || !parse_here_string(buffer, tokenizer, token)
                memset(colors.data + token.start, xx color, token.len);

            quote_color := ifx token.type == .string_literal then COLOR_MAP[Ficus_Token.Type.punctuation] else COLOR_MAP[Ficus_Token.Type.error];
            memset(colors.data + token.start, xx quote_color, token.sublen);
            memset(colors.data + token.start + token.len - token.sublen, xx quote_color, token.sublen);
        }
        else if token.type == .declaration { // `:` guaranteed to be next char in buffer
            memset(colors.data + token.start, xx color, token.len);

            token = ficus_get_next_token(tokenizer);
            assert(token.type == .word); // solo `:` should be treated as a word, under normal conditions
            if token.len != 1  // junk after `:` on declaration
                token.type = .error;
            else
                token.type = .punctuation;
            color = COLOR_MAP[token.type];
            memset(colors.data + token.start, xx color, token.len);
        }
        else if token.type == .word_with_stack {
            memset(colors.data + token.start, xx color, token.sublen);
            memset(colors.data + token.start + token.sublen, xx COLOR_MAP[Ficus_Token.Type.punctuation], 1);
            memset(colors.data + token.start + token.sublen + 1, xx COLOR_MAP[Ficus_Token.Type.word], token.len - token.sublen - 1);
        }
        else {
            memset(colors.data + token.start, xx color, token.len);
        }
    }
}

#scope_file

parse_here_string :: (using buffer: *Buffer, using tokenizer: *Ficus_Tokenizer, token: Ficus_Token) -> handled: bool{
    assert(token.type == .string_literal);
    if token.len < token.sublen * 2  return false;

    identifier : string = ---;
    identifier.data = buffer.bytes.data + token.start + 1;
    identifier.count = token.sublen - 1;
    language := language_from_extension(identifier);

    add_buffer_region(buffer, token.start, token.start + token.len, false, 1, .here_string);

    return maybe_highlight_inner_language(buffer, language, token.start + token.sublen, token.len - token.sublen * 2);
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
    .PUNCTUATION,   // begin_sequence
    .PUNCTUATION,   // end_sequence
    .DEFAULT,       // word
    .TYPE,          // word_with_stack
    .VALUE,         // number_literal
    .STRING,        // string_literal
];

#run assert(enum_highest_value(Ficus_Token.Type) == COLOR_MAP.count - 1);
