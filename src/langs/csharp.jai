CSharp :: struct {
    tokens: [..] Token;
    token_index: int;

    nodes: [..] CSNode;
    current_parent_node_index: int;
    attributes_to_assign: [..] int;
    current_flags: CSNode.Flags;
    current_type_token_index: int;

    done_with_using_block := false;
}

#add_context csharp: CSharp;


highlight_csharp_syntax :: (using buffer: *Buffer) {
    tokenizer := get_tokenizer(buffer);
    highlight_csharp_syntax(buffer, tokenizer);
}

highlight_csharp_syntax :: (using buffer: *Buffer, start_index: s32, count: s32) {
    tokenizer := New(Tokenizer, initialized=false,, temp);
    tokenizer.* = .{
        buf        = cast(string) bytes,
        max_t      = bytes.data + start_index + count,
        t          = bytes.data + start_index,
    };
    add_recent_token(tokenizer, .{0, 0, .eof, "", .DEFAULT});
    highlight_csharp_syntax(buffer, tokenizer);
}



highlight_csharp_syntax :: (using buffer: *Buffer, tokenizer: *Tokenizer) {
    using context.csharp;

    print("%\n", frame_time);

    tokenize_csharp(buffer, tokenizer);

    if tokens.count == 0  return;

    for * nodes  array_reset(*it.children);
    array_reset(*nodes);
    array_reset(*attributes_to_assign);
    root_node := array_add(*nodes);
    current_parent_node_index = 0;
    current_flags = .NONE;
    done_with_using_block = false;

    token_index = 0;
    parse_csharp();

    for tokens
        memset(colors.data + it.start, xx it.color, it.len);
}

is_error :: () -> bool #expand {
    using context.csharp;

    if `error != "" {
        print("% @ % %\n", `error, tokens[token_index].start, tokens[token_index].as_string);
        return true;
    }
    else {
        return false;
    }
}

parse_csharp :: () {
    using context.csharp;

    while true {
        ends_using_block := true;
        defer if ends_using_block  done_with_using_block = true;

        token, ok := peek_token();
        if !ok  break;

        error := "";

        start_token_index := token_index;

        if token.type == {
            case .keyword;
                if token.keyword == {
                    case .kw_using;
                        ends_using_block = false;
                        if done_with_using_block {
                            // @TODO
                        }
                        else {
                            eat_token();
                            error := parse_using_directive_tail();
                            if !is_error() {
                                paint_tokens(start_token_index, 1, .directive);
                                // Make node
                                current_flags = .NONE;
                            }
                            continue;
                        }

                    case .kw_class;
                        //paint_token(.MODIFIER_KEYWORD);
                        eat_token();
                        error := ifx current_flags & .RECORD then parse_record_class() else parse_class();
                        if !is_error() {
                            // Make node
                            current_flags = .NONE;
                        }
                        continue;
                }

            case .punctuation;
                if token.punctuation == {
                    case .l_bracket;
                        eat_token();
                        error = parse_attribute_tail();
                        if !is_error() {
                            array_add(*attributes_to_assign, nodes.count);
                            node := array_add(*nodes);
                            node.start_token_index = start_token_index;
                            node.end_token_index = token_index - 1;
                            node.type = .ATTRIBUTE;
                            current_flags |= .HAS_ATTRIBUTES;
                            paint_tokens(node.start_token_index, 2, .attribute, .HIGHLIGHT);
                            paint_tokens(node.end_token_index, 1, .attribute, .HIGHLIGHT);
                        }
                        continue;
                }

            case .modifier_keyword;
                flag := flag_from_modifier(token.keyword);
                if flag == .NONE {
                    print("Error: got .NONE from flag_from_modifier");
                }
                else {
                    current_flags |= flag;
                }
                eat_token();
                continue;

            case .type_keyword;

            case .identifier;

            case .directive;
                ends_using_block = false;
        }

        eat_token();
    }
}


parse_record_class :: () -> error: string {
    // @TODO
    return "";
}



parse_class :: () -> error: string {
    identifier, is_generic := eat_generic_identifier();
    if !identifier  return "Expected identifier in parse_class";

    token := expect_token();
    if is_operation(token, .colon) {
        eat_token();

        // Parent class + interfaces
        eat_generic_identifier();
        token = expect_token();
        while is_punctuation(token, .comma) {
            eat_token();
            eat_generic_identifier();
            token = expect_token();
        }
    }

    while is_generic && is_keyword(token, .kw_where) {
        eat_token();
        eat_identifier();
        eat_operation(.colon);

        eat_generic_identifier();
        token = expect_token();
        while is_punctuation(token, .comma) {
            eat_token();
            eat_generic_identifier();
            token = expect_token();
        }
    }

    eat_punctuation(.l_brace);

    return parse_body();
}


parse_body :: () -> error: string {
    using context.csharp;

    current_flags = .NONE;

    while true {
        start_token_index := token_index;

        token := expect_token();
        if token.type == {
            case .modifier_keyword;
                flag := flag_from_modifier(token.keyword);
                if flag == .NONE
                    print("Error: got .NONE from flag_from_modifier");
                else
                    current_flags |= flag;
                eat_token();
                continue;

            case .directive;
                eat_token();
                while true {
                    token := expect_token();
                    eat_token();
                    if token.type == .identifier
                        paint_last_token(.directive);
                    else if token.type == .eol
                        break;
                }
                continue;

            case .identifier;
                paint_token(.type_keyword);
                #through;

            case .type_keyword;
                current_type_token_index = token_index;
                eat_token();
                parse_declaration();
                continue;

            case .punctuation;
                if token.punctuation == {
                    case .r_brace;
                        eat_token();
                        return "";

                    case .l_bracket;
                        eat_token();
                        error := parse_attribute_tail();
                        if !is_error() {
                            array_add(*attributes_to_assign, nodes.count);
                            node := array_add(*nodes);
                            node.start_token_index = start_token_index;
                            node.end_token_index = token_index - 1;
                            node.type = .ATTRIBUTE;
                            current_flags |= .HAS_ATTRIBUTES;
                            paint_tokens(node.start_token_index, 2, .attribute, .HIGHLIGHT);
                            paint_tokens(node.end_token_index, 1, .attribute, .HIGHLIGHT);
                        }
                        continue;
                }
        }

        eat_token();
    }

    return "";
}

parse_declaration :: () -> error: string {
    using context.csharp;

    if eat_array_punctuation()  current_flags |= .IS_ARRAY;

    name := eat_identifier();

    token := expect_token();
    if token.type == {
        case .punctuation;
            if token.punctuation == {
                case .semicolon;
                    eat_token();
                    return "";

                case .l_paren;
                    eat_token();
                    return parse_function();

                case .l_brace;
                    eat_token();
                    return parse_property();
            }

        case .operation;
            if token.operation == .equal {
                eat_token();
                error := parse_expression(.semicolon);
                if error  return error;

                eat_token();
                return "";
            }
    }

    return "Unexpected token in declaration";
}

parse_function :: () -> error: string {
    using context.csharp;

    error := parse_function_header_tail();
    if error  return error;

    eat_punctuation(.l_brace);
    return parse_body();
}


parse_function_header_tail :: () -> error: string {
    using context.csharp;

    assert(is_punctuation(peek_token(-1), .l_paren));

    while true {
        is_named_parameter := false;
        parameter_name := expect_token();
        if parameter_name.type == .identifier {
            maybe_colon := expect_token(1);
            is_named_parameter = is_operation(maybe_colon, .colon);
        }

        if is_named_parameter  eat_tokens(2);

        error := parse_expression(.r_paren, .comma);
        if error  return error;

        comma_or_paren := expect_token();
        if comma_or_paren.punctuation == {
            case .r_paren;
                eat_token();
                return "";

            case .comma;
                eat_token();
        }
    }

    return ""; // Unreachable
}

parse_property :: () -> error: string {
    return parse_body();
}

parse_using_directive_tail :: () -> error: string {
    using context.csharp;

    token := expect_token();

    if is_modifier(token, .kwm_static) {
        current_flags |= .STATIC;
        token = expect_token();
    }

    if token.type != .identifier  return "using should be followed by identifier";

    eat_token();

    identifier := token;

    token = expect_token();

    if token.type == .punctuation  if token.punctuation == {
        case .semicolon;
            eat_token();
            return "";

        case .period;
            eat_token();
            error := parse_identifier_dot_chain(.semicolon, identifier);
            if error  return error;

            eat_token();
            return "";
    }

    if is_operation(token, .equal) {
        eat_token();
        error := parse_identifier_dot_chain(.semicolon);
        if error  return error;

        eat_token();
        return "";
    }

    return "Expected . or = or ; in using";
}


parse_identifier_dot_chain :: (terminator: Punctuation, first_identifier : *Token = null) -> error: string {
    while true {
        eat_identifier();

        token := expect_token();
        if token.type == .punctuation {
            if token.punctuation == terminator {
                return "";
            }
            else if token.punctuation == .period {
                eat_token();
                continue;
            }
        }

        return "Unexpected token in identifier dot chain";
    }
}


parse_attribute_tail :: () -> error: string {
    using context.csharp;

    identifier := eat_identifier();
    expect_paren_or_bracket := expect_token();

    if expect_paren_or_bracket.type == .punctuation {
        if expect_paren_or_bracket.punctuation == .r_bracket {
            // [attribute]
            eat_token();
            return "";
        }
        else if expect_paren_or_bracket.punctuation == .l_paren {
            // [attribute(positional_parameters, name_parameter = value)]
            error := parse_attribute_call(identifier);
            if error  return error;

            token := eat_punctuation(.r_bracket);
            token.type = .attribute;
            token.color = .HIGHLIGHT;
            return "";
        }
    }

    return "Unexpected token in Attribute";
}


parse_attribute_call :: (identifier : *Token = null) -> error: string {
    using context.csharp;

    if !identifier
        identifier = eat_identifier();
    else
        assert(peek_token(-1).type == .identifier);

    eat_punctuation(.l_paren);

    while true {
        is_named_parameter := false;
        parameter_name := expect_token();
        if parameter_name.type == .identifier {
            maybe_equals := expect_token(1);
            is_named_parameter = is_operation(maybe_equals, .equal);
        }

        if is_named_parameter  eat_tokens(2);

        error := ifx is_named_parameter
                 then parse_attribute_assignment(parameter_name)
                 else parse_expression(.r_paren, .comma);
        if error  return error;

        comma_or_paren := expect_token();
        if comma_or_paren.punctuation == {
            case .r_paren;
                eat_token();
                return "";

            case .comma;
                eat_token();
        }
    }

    return ""; // Unreachable
}


parse_attribute_assignment :: (identifier : *Token = null) -> error: string {
    if !identifier {
        identifier = eat_identifier();
        eat_operation(.equal);
    }
    else {
        assert(peek_token(-2).type == .identifier);
        assert(is_operation(peek_token(-1), .equal));
    }

    return parse_expression(.r_paren, .comma);
}


parse_expression :: (terminator1: Punctuation, terminator2 : Punctuation = cast(Punctuation) 65535) -> error: string {
    token, ok := peek_token();
    if !ok  return "EOF in expression";

    while ok {
        if #complete token.type == {
            case .invalid;
                eat_token();
                return "Invalid token in expression";

            case .punctuation;
                if token.punctuation == terminator1 || token.punctuation == terminator2
                    return "";

                if #complete token.punctuation == {
                    case .l_paren;
                    eat_token();
                    error := parse_expression(.r_paren);
                    if error  return error;
                    eat_token();

                    case .l_brace;
                    eat_token();
                    error := parse_expression(.r_brace);
                    if error  return error;
                    eat_token();

                    case .l_bracket;
                    eat_token();
                    error := parse_expression(.r_bracket);
                    if error  return error;
                    eat_token();

                    case .period;
                    eat_token();

                    case .semicolon;
                    return "Unexpected ; in expression";

                    case .comma;
                    return "Unexpected , in expression";

                    case .backslash;
                    return "Unexpected \\ in expression";

                    case .r_paren;
                    return "Unexpected ) in expression";

                    case .r_brace;
                    return "Unexpected } in expression";

                    case .r_bracket;
                    return "Unexpected ] in expression";
                }

            case .operation;
                if is_assignment_operation(token.operation)
                    return "Unexpected assignment in expression";

                eat_token();

            case .keyword;
                if token.keyword == {
                    case .kw_sizeof; #through;
                    case .kw_typeof;
                        eat_token();

                    case;
                        return "Unexpected keyword in expression";
                }

            case .value_keyword; #through;
            case .type_keyword; #through;
            case .identifier; #through;
            case .string_literal; #through;
            case .char_literal; #through;
            case .number; #through;
            case .multiline_comment; #through;
            case .function_like; #through;
            case .attribute;
                eat_token();

            case .comment;
                return "Unexpected // in expression";

            case .modifier_keyword;
                return "Unexpected modifier keyword in expression";

            case .jump_keyword;
                return "Unexpected jump keyword in expression";

            case .directive;
                return "Unexpected directive in expression";

            case .eof;
                return "Unexpected EOF in expression";

            case .eol;
                return "Unexpected EOL in expression";
        }

        token, ok = peek_token();
    }

    return "EOF in expression";
}


paint_tokens :: (start_index: int, count: int, type: Token.Type, color: Code_Color) {
    using context.csharp;

    for 0 .. count - 1 {
        token := *tokens[start_index + it];
        token.type = type;
        token.color = color;
    }
}

paint_tokens :: (start_index: int, count: int, type: Token.Type) {
    using context.csharp;

    for 0 .. count - 1 {
        token := *tokens[start_index + it];
        token.type = type;
        token.color = COLOR_MAP[type];
    }
}

paint_tokens :: (start_index: int, count: int, color: Code_Color) {
    using context.csharp;

    for 0 .. count - 1 {
        token := *tokens[start_index + it];
        token.color = color;
    }
}

paint_last_token :: (type: Token.Type, color: Code_Color) {
    using context.csharp;
    token := *tokens[token_index - 1];
    token.type = type;
    token.color = color;
}

paint_last_token :: (type: Token.Type) {
    using context.csharp;
    token := *tokens[token_index - 1];
    token.type = type;
    token.color = COLOR_MAP[type];
}

paint_last_token :: (color: Code_Color) {
    using context.csharp;
    token := *tokens[token_index - 1];
    token.color = color;
}

paint_token :: (type: Token.Type, color: Code_Color) {
    using context.csharp;
    token := *tokens[token_index];
    token.type = type;
    token.color = color;
}

paint_token :: (type: Token.Type) {
    using context.csharp;
    token := *tokens[token_index];
    token.type = type;
    token.color = COLOR_MAP[type];
}

paint_token :: (color: Code_Color) {
    using context.csharp;
    token := *tokens[token_index];
    token.color = color;
}

peek_token :: (offset := 0) -> *Token, ok: bool {
    using context.csharp;

    if token_index + offset < tokens.count
        return *tokens[token_index + offset], true;
    else
        return null, false;
}

eat_token :: () -> eof: bool {
    return inline eat_tokens(1);
}

eat_tokens :: (count: int) -> eof: bool {
    using context.csharp;
    token_index += count;
    return token_index >= tokens.count;
}

get_token :: () -> *Token, ok: bool {
    token, ok := peek_token();
    if ok {
        eat_tokens(1);
        return token, true;
    }
    else {
        return null, false;
    }
}


#scope_module


tokenize_csharp :: (using buffer: *Buffer, tokenizer: *Tokenizer) {
    using context.csharp;
    array_reset(*tokens);

    while true {
        token := get_next_token(tokenizer);
        if token.type == .eof  break;

        token.color = COLOR_MAP[token.type];

        if token.type == .comment || token.type == .multiline_comment {
            memset(colors.data + token.start, xx token.color, token.len);
            continue;
        }

        array_add(*tokens, token);

        // Only record .eol where it is needed.
        if token.type == {
            case .directive;
                tokenizer.return_eol = true;

            case .eol;
                tokenizer.return_eol = false;
        }
    }
}

CSNode :: struct {
    start_token_index: int;
    end_token_index: int;

    parent: int;
    children: [..] int;

    type: Type;
    flags: Flags;

    Type :: enum {
        DECLARATION;
        ASSIGNMENT;
        STATEMENT;
        DIRECTIVE;
        ATTRIBUTE;
    };

    Flags :: enum_flags {
        NONE :: 0;

        // Modifier keywords
        ABSTRACT :: 1;
        ASYNC;
        DELEGATE;
        CONST;
        EVENT;
        EXTERN;
        FILE;
        GLOBAL;
        INTERNAL;
        NEW;
        OVERRIDE;
        PRIVATE;
        PROTECTED;
        PUBLIC;
        READONLY;
        RECORD;
        SEALED;
        STATIC;
        UNSAFE;
        VIRTUAL;
        VOLATILE;

        // Misc
        IS_ARRAY;
        HAS_ATTRIBUTES;
    }
}


flag_from_modifier :: (modifier: Keyword) -> CSNode.Flags {
    if modifier == {
        case .kwm_abstract;  return .ABSTRACT;
        case .kwm_async;     return .ASYNC;
        case .kwm_delegate;  return .DELEGATE;
        case .kwm_const;     return .CONST;
        case .kwm_event;     return .EVENT;
        case .kwm_extern;    return .EXTERN;
        case .kwm_file;      return .FILE;
        case .kwm_global;    return .GLOBAL;
        case .kwm_internal;  return .INTERNAL;
        case .kwm_new;       return .NEW;
        case .kwm_override;  return .OVERRIDE;
        case .kwm_private;   return .PRIVATE;
        case .kwm_protected; return .PROTECTED;
        case .kwm_public;    return .PUBLIC;
        case .kwm_readonly;  return .READONLY;
        case .kwm_record;    return .RECORD;
        case .kwm_sealed;    return .SEALED;
        case .kwm_static;    return .STATIC;
        case .kwm_unsafe;    return .UNSAFE;
        case .kwm_virtual;   return .VIRTUAL;
        case .kwm_volatile;  return .VOLATILE;
    }

    return .NONE;
}


csharp_is_keyword_which_can_braceless_indent :: (buffer: *Buffer, first_token_pos: s64, cursor_pos: s64) -> bool {
    assert(cursor_pos > first_token_pos);

    /* We don't have a KEYWORDS array for csharp, so check disabled for now
    #run {
        // Check that the short-circuit assumptions we use below still hold
        assert(array_count_starts_with(KEYWORDS, "f") == 1);
        assert(array_count_starts_with(KEYWORDS, "w") == 1);
        assert(array_count_starts_with(KEYWORDS, "el") == 1);
        assert(array_count_starts_with(KEYWORDS, "th") == 1);
    }
    */

    i := first_token_pos;
    length := cursor_pos - i;
    if buffer.colors[i] == xx Code_Color.KEYWORD {
        if length >= 2 && buffer.bytes[i] == #char "i" && buffer.bytes[i+1] == #char "f" && buffer.bytes[i+2] != #char "x" // if
        || length >= 3 && buffer.bytes[i] == #char "f" // for
        || length >= 5 && buffer.bytes[i] == #char "w" // while
            return true;
    }

    i = cursor_pos - 1;
    while i > first_token_pos && is_whitespace_char(buffer.bytes[i])
        i -= 1;

    if buffer.colors[i] == xx Code_Color.KEYWORD {
        while i > first_token_pos && buffer.colors[i - 1] == xx Code_Color.KEYWORD
            i -= 1;
        length = cursor_pos - i;
        return length >= 4 && buffer.bytes[i] == #char "e" && buffer.bytes[i+1] == #char "l" // else
            || length >= 4 && buffer.bytes[i] == #char "t" && buffer.bytes[i+1] == #char "h"; // then
    }

    return false;
}



tokenize_csharp_for_indentation :: (using buffer: Buffer) -> [] Indentation_Token /* temp */ {
    tokens: [..] Indentation_Token;
    tokens.allocator = temp;

    tokenizer := get_tokenizer(buffer);

    while true {
        src := get_next_token(tokenizer);

        token: Indentation_Token = ---;
        token.start = src.start;
        token.len   = src.len;

        if src.type == {
            case .punctuation;
                if src.punctuation == {
                    case .l_paren;      token.type = .open;  token.kind = .paren;
                    case .l_bracket;    token.type = .open;  token.kind = .bracket;
                    case .l_brace;      token.type = .open;  token.kind = .brace;

                    case .r_paren;      token.type = .close; token.kind = .paren;
                    case .r_bracket;    token.type = .close; token.kind = .bracket;
                    case .r_brace;      token.type = .close; token.kind = .brace;

                    case;               continue;
                }

            case .multiline_comment;    token.type = .maybe_multiline;
            case .eof;                  token.type = .eof;  // to guarantee we always have indentation tokens
            case;                       token.type = .unimportant;
        }

        array_add(*tokens, token);

        if src.type == .eof break;
    }

    return tokens;
}


#scope_file


get_tokenizer :: (using buffer: Buffer) -> *Tokenizer {
    tokenizer := New(Tokenizer,, temp);

    tokenizer.buf   = cast(string) bytes;
    tokenizer.max_t = bytes.data + bytes.count;
    tokenizer.t     = bytes.data;
    add_recent_token(tokenizer, .{0, 0, .eof, "", .DEFAULT});

    return tokenizer;
}


get_next_token :: (using tokenizer: *Tokenizer) -> Token {
    if tokenizer.return_eol
        t = eat_white_space_no_newline(t, max_t);
    else
        t = eat_white_space(t, max_t);

    token: Token;
    token.start = cast(s32) (t - buf.data);
    token.as_string.data = buf.data + token.start;
    token.type  = .eof;
    if t >= max_t return token;

    start_t = t;

    // Look at the first char as if it's ASCII (if it isn't, this is just a text line)
    char := <<t;

    if is_alpha(char) || char == #char "_" {
        parse_identifier(tokenizer, *token, true);
    } else if is_digit(char) {
        parse_number(tokenizer, *token);
    } else if char == #char "\n" {
        token.type = .eol; t += 1;
    } else if char == {
        // https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/operators/
        case #char "=";  parse_equal                 (tokenizer, *token);
        case #char "-";  parse_minus                 (tokenizer, *token);
        case #char "+";  parse_plus                  (tokenizer, *token);
        case #char "*";  parse_asterisk              (tokenizer, *token);
        case #char "<";  parse_less_than             (tokenizer, *token);
        case #char ">";  parse_greater_than          (tokenizer, *token);
        case #char "!";  parse_bang                  (tokenizer, *token);
        case #char "#";  parse_directive(tokenizer, *token);
        case #char "\""; parse_string_literal        (tokenizer, *token);
        case #char "'";  parse_char_literal          (tokenizer, *token);
        case #char "/";  parse_slash_or_comment      (tokenizer, *token);
        case #char "&";  parse_ampersand             (tokenizer, *token);
        case #char "|";  parse_pipe                  (tokenizer, *token);
        case #char "%";  parse_percent               (tokenizer, *token);
        case #char "@";  parse_at                    (tokenizer, *token);
        case #char "^";  parse_caret                 (tokenizer, *token);
        case #char "$";  parse_dollar                (tokenizer, *token);
        case #char ":";  token.type = .operation;   token.operation = .colon;       t += 1;
        case #char "?";  token.type = .operation;   token.operation = .question;    t += 1;
        case #char "~";  token.type = .operation;   token.operation = .tilde;       t += 1;

        case #char ";";  token.type = .punctuation; token.punctuation = .semicolon; t += 1;
        case #char "\\"; token.type = .punctuation; token.punctuation = .backslash; t += 1;
        case #char ",";  token.type = .punctuation; token.punctuation = .comma;     t += 1;
        case #char ".";  token.type = .punctuation; token.punctuation = .period;    t += 1;
        case #char "{";  token.type = .punctuation; token.punctuation = .l_brace;   t += 1;
        case #char "}";  token.type = .punctuation; token.punctuation = .r_brace;   t += 1;
        case #char "(";  token.type = .punctuation; token.punctuation = .l_paren;   t += 1;
        case #char ")";  token.type = .punctuation; token.punctuation = .r_paren;   t += 1;
        case #char "[";  token.type = .punctuation; token.punctuation = .l_bracket; t += 1;
        case #char "]";  token.type = .punctuation; token.punctuation = .r_bracket; t += 1;

        case;            token.type = .invalid; t += 1;
    }

    if t >= max_t then t = max_t;
    token.len = cast(s32) (t - start_t);
    token.as_string.count = token.len;

    return token;
}

parse_identifier :: (using tokenizer: *Tokenizer, token: *Token, check_for_keyword: bool) {
    token.type = .identifier;

    identifier := read_identifier_string(tokenizer);

    if check_for_keyword && identifier.count <= MAX_KEYWORD_LENGTH {
        kw_token, ok := table_find(*KEYWORD_MAP, identifier);
        if ok { token.type = kw_token.type; token.keyword = kw_token.keyword; return; }
    }
}

is_hex :: inline (c: u8) -> bool {
    return is_digit(c) || (c >= #char "a" && c <= #char "f") || (c >= #char "A" && c <= #char "F");
}

// https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/builtin-types/integral-numeric-types
// https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/builtin-types/floating-point-numeric-types
parse_number :: (using tokenizer: *Tokenizer, token: *Token) {
    token.type = .number;

    is_floating_point_suffix :: (c: u8) -> bool {
        return c == #char "f" || c == #char "F" || c == #char "d" || c == #char "D" || c == #char "m" || c == #char "M";
    }

    // Consecutive underscores are allowed in numbers but they can't end in one.
    is_valid_underscore :: (t: *u8, max_t: *u8, allowed: (u8) -> bool) -> bool {
        next := t + 1;
        return <<t == #char "_" && (next < max_t && (allowed(<<next) || <<next == #char "_"));
    }

    t += 1;
    if t >= max_t return;

    if <<t == #char "x" || <<t == #char "X" {
        // Hex
        t += 1;
        while t < max_t && (is_hex(<<t) || is_valid_underscore(t, max_t, is_hex)) t += 1;
        return;
    } else if <<t == #char "b" || <<t == #char "B" {
        // Binary
        t += 1;
        is_binary :: inline (c: u8) -> bool { return c == #char "1" || c == #char "0"; }
        while t < max_t && (is_binary(<<t) || is_valid_underscore(t, max_t, is_binary)) t += 1;
        return;
    }

    // Eat initial digits/underscores
    while t < max_t && (is_digit(<<t) || is_valid_underscore(t, max_t, is_digit)) {
        t += 1;
    }
    if t >= max_t return;

    if <<t == #char "." {
        // Float, double or decimal
        // First char after a decimal point must be a digit(cannot be an underscore).
        t += 1;
        if t >= max_t || !is_digit(<<t) { token.type = .invalid; return; }

        // Eat digits/underscores after the decimal point
        t += 1;
        while t < max_t && (is_digit(<<t) || is_valid_underscore(t, max_t, is_digit)) {
            t += 1;
        }

        if t >= max_t return;

        // Exponent
        if <<t == #char "e" || <<t == #char "E" {
            t += 1;
            if t >= max_t return;

            if <<t == #char "+" || <<t == #char "-" {
              t += 1;
              if t >= max_t return;
            }

            while t < max_t && (is_digit(<<t) || is_valid_underscore(t, max_t, is_digit)) {
                t += 1;
            }
            if t >= max_t return;
        }

        // Floating point suffixes
        if is_floating_point_suffix(<<t) t += 1;
    } else {
        if is_floating_point_suffix(<<t) {
            // Floating point suffixes (can occur without a decimal point)
            t += 1;
        } else {
            // Integer suffixes
            if <<t == #char "l" || <<t == #char "L" { // l, L
                t += 1;
                if t >= max_t return;

                if <<t == #char "u" || <<t == #char "U" {  // lu, lU, Lu, LU
                    t += 1;
                }
            } else if <<t == #char "u" || <<t == #char "U" { // u, U
                t += 1;
                if t >= max_t return;

                if <<t == #char "l" || <<t == #char "L" {  // ul, uL, Ul, UL
                    t += 1;
                }
            }
        }
    }
}

parse_equal :: (using tokenizer: *Tokenizer, token: *Token) {
    token.type = .operation;
    token.operation = .equal;

    t += 1;
    if t >= max_t return;

    if <<t == #char "=" {
        token.operation = .equal_equal;
        t += 1;
    }
}


parse_minus :: (using tokenizer: *Tokenizer, token: *Token) {
    token.type = .operation;
    token.operation = .minus;

    t += 1;
    if t >= max_t return;

    if <<t == {
        case #char "=";
            token.operation = .minus_equal;
            t += 1;
        case #char ">";
            // https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/unsafe-code?#pointer-types
            token.operation = .arrow;
            t += 1;
        case #char "-";
            token.operation = .minus_minus;
            t += 1;
    }
}

parse_plus :: (using tokenizer: *Tokenizer, token: *Token) {
    token.type = .operation;
    token.operation = .plus;

    t += 1;
    if t >= max_t return;

    if <<t == {
        case #char "=";
            token.operation = .plus_equal;
            t += 1;
        case #char "+";
            token.operation = .plus_plus;
            t += 1;
    }
}

parse_asterisk :: (using tokenizer: *Tokenizer, token: *Token) {
    token.type = .operation;
    token.operation = .asterisk;

    t += 1;
    if t >= max_t return;

    if <<t == #char "=" {
        token.operation = .asterisk_equal;
        t += 1;
    }
}

parse_less_than :: (using tokenizer: *Tokenizer, token: *Token) {
    token.type = .operation;
    token.operation = .less_than;

    t += 1;
    if t >= max_t return;

    if <<t == {
        case #char "=";
            token.operation = .less_than_equal;
            t += 1;
        case #char "<";
            token.operation = .double_less_than;
            t += 1;
    }
}

parse_greater_than :: (using tokenizer: *Tokenizer, token: *Token) {
    token.type = .operation;
    token.operation = .greater_than;

    t += 1;
    if t >= max_t return;

    if <<t == {
        case #char "=";
            token.operation = .greater_than_equal;
            t += 1;
    }
}

parse_bang :: (using tokenizer: *Tokenizer, token: *Token) {
    token.type = .operation;
    token.operation = .bang;

    t += 1;
    if t >= max_t return;

    if <<t == {
        case #char "=";
            token.operation = .bang_equal;
            t += 1;
    }
}

parse_directive :: (using tokenizer: *Tokenizer, token: *Token) {
    token.type = .identifier;

    t += 1;
    t = eat_white_space(t, max_t);  // There may be spaces between the # and the name
    if !is_alpha(<<t) return;

    directive := read_identifier_string(tokenizer);

    while t < max_t && is_alnum(<<t) t += 1;
    if t >= max_t return;

    // Check if it's one of the existing directives
    if directive.count > MAX_DIRECTIVE_LENGTH return;
    token_directive, ok := table_find(*PREPROCESSOR_DIRECTIVES_MAP, directive);
    if ok {
        token.type = .directive;
        token.directive = token_directive;
    }
}

parse_string_literal :: (using tokenizer: *Tokenizer, token: *Token) {
    token.type = .string_literal;

    escape_seen := false;

    t += 1;
    while t < max_t && <<t != #char "\n" {
        if <<t == #char "\"" && !escape_seen break;
        escape_seen = !escape_seen && <<t == #char "\\";
        t += 1;
    }
    if t >= max_t return;

    t += 1;
}

// https://learn.microsoft.com/en-us/dotnet/csharp/programming-guide/strings/
is_valid_character_escape_character :: (c: u8) -> bool {
    return (
        c == #char "'" ||
        c == #char "\"" ||
        c == #char "\\" ||
        c == #char "0" ||
        c == #char "a" ||
        c == #char "b" ||
        c == #char "f" ||
        c == #char "n" ||
        c == #char "r" ||
        c == #char "t" ||
        c == #char "v" ||
        c == #char "u" ||
        // c == #char "U" || // Only supported by strings not characters
        c == #char "x"
    );
}

// https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/builtin-types/char
parse_char_literal :: (using tokenizer: *Tokenizer, token: *Token) {
    token.type = .invalid;

    escape_seen := false;

    t += 1;
    if t >= max_t || <<t == #char "\n" return;

    if <<t == #char "\\" {
        escape_seen = true;
        t += 1;
        if t >= max_t || <<t == #char "\n" return;
    } else if <<t == #char "'" {
        // Unescaped single quote without a character
        t += 1; // Invalid '
        return;
    }

    if escape_seen {
        if !is_valid_character_escape_character(<<t) {
            return;
        } else if <<t == #char "u" {
            // u must be followed by 4 hex characters
            t += 1; count := 0;
            while t < max_t && count < 4 {
                if !is_hex(<<t) { t += 1; return; }
                count += 1;
                t += 1;
            }
            if t >= max_t || <<t == #char "\n" return;
        } else if <<t ==#char "x" {
            t += 1;
            // x must be followed by at least one hex character
            if t >= max_t || !is_hex(<<t) return;
            while t < max_t && is_hex(<<t) t += 1;
        } else {
            // A single valid character after the escape like '\n'
            t += 1;
        }
    } else {
        t += 1; // Unescaped single character
    }

    if t >= max_t || <<t == #char "\n" || <<t != #char "'" return;

    token.type = .char_literal;
    t += 1; // Ending '
}

parse_slash_or_comment :: (using tokenizer: *Tokenizer, token: *Token) {
    token.type = .operation;
    token.operation = .slash;

    t += 1;
    if t >= max_t return;

    if <<t == {
        case #char "=";
            token.operation = .slash_equal;
            t += 1;
        case #char "/";
            token.type = .comment;
            t += 1;
            while t < max_t && <<t != #char "\n" t += 1;
        case #char "*";
            token.type = .multiline_comment;
            t += 1;
            while t + 1 < max_t {
                if <<t == #char "*" && <<(t + 1) == #char "/" {
                  t += 2;
                  break;
                }
                t += 1;
            }
    }
}

parse_ampersand :: (using tokenizer: *Tokenizer, token: *Token) {
    token.type = .operation;
    token.operation = .ampersand;

    t += 1;
    if t >= max_t return;

    if <<t == {
        case #char "=";
            token.operation = .ampersand_equal;
            t += 1;
        case #char "&";
            token.operation = .double_ampersand;
            t += 1;
    }
}

parse_pipe :: (using tokenizer: *Tokenizer, token: *Token) {
    token.type = .operation;
    token.operation = .pipe;

    t += 1;
    if t >= max_t return;

    if <<t == {
        case #char "=";
            token.operation = .pipe_equal;
            t += 1;
        case #char "|";
            token.operation = .double_pipe;
            t += 1;
    }
}

parse_percent :: (using tokenizer: *Tokenizer, token: *Token) {
    token.type = .operation;
    token.operation = .percent;

    t += 1;
    if t >= max_t return;

    if <<t == {
        case #char "=";
            token.operation = .percent_equal;
            t += 1;
    }
}

parse_verbatim_string_literal :: (using tokenizer: *Tokenizer, token: *Token) {
    token.type = .string_literal;

    escape_seen := false;

    t += 1;
    while t < max_t && <<t != #char "\n" {
        if escape_seen && <<t != #char "\"" { t -= 1; break; }
        escape_seen = !escape_seen && <<t == #char "\"";
        t += 1;
    }
    if t >= max_t return;

    t += 1;
}

// https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/tokens/verbatim
// https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/language-specification/attributes
parse_at :: (using tokenizer: *Tokenizer, token: *Token) {
    token.type = .invalid;

    t += 1;
    if t >= max_t return;

    if <<t == #char "$" {
        // Verbatim interpolated string
        parse_dollar(tokenizer, token, true);
    } else if <<t == #char "\"" {
        // Verbatim string
        parse_verbatim_string_literal(tokenizer, token);
    } else if is_alpha(<<t) || <<t == #char "_" {
        // Identifier or disambiguate attribute
        parse_identifier(tokenizer, token, check_for_keyword = false);
    }
}

// Interpolated string
// The enclosed identifiers and braces are not parsed
parse_dollar :: (using tokenizer: *Tokenizer, token: *Token, verbatim := false) {
    token.type = .invalid;

    t += 1;
    if t >= max_t return;

    if <<t == #char "@" {
        // Interpolated verbatim string
        parse_at(tokenizer, token);
    } else if <<t == #char "\"" {
        if verbatim {
            // Verbatim interpolated string
            parse_verbatim_string_literal(tokenizer, token);
        } else {
            // Interpolated string
            parse_string_literal(tokenizer, token);
        }
    }
}

parse_caret :: (using tokenizer: *Tokenizer, token: *Token) {
    token.type = .operation;
    token.operation = .caret;

    t += 1;
    if t >= max_t return;

    if <<t == {
        case #char "=";
            token.operation = .caret_equal;
            t += 1;
    }
}

read_identifier_string :: (using tokenizer: *Tokenizer) -> string {
    identifier: string;
    identifier.data = t;

    while t < max_t && is_alnum(<<t) {
        t += 1;
    }
    if t >= max_t then t = max_t;
    identifier.count = t - identifier.data;

    return identifier;
}

eat_white_space_no_newline :: inline (start: *u8, max_t: *u8) -> *u8 {
    t := start;
    while t < max_t && (t.* != #char "\n" && is_white_space(t.*)) {
        t += 1;
    }
    return t;
}

eat_white_space :: inline (start: *u8, max_t: *u8) -> *u8 {
    t := start;
    while t < max_t && is_white_space(t.*) {
        t += 1;
    }
    return t;
}

get_recent_token :: (tokenizer: *Tokenizer, offset: int) -> *Token {
    assert(offset <= 0);
    i := tokenizer.recent_token_head + offset;
    if i < 0  i += tokenizer.recent_tokens.count;
    return *tokenizer.recent_tokens[i];
}

add_recent_token ::(tokenizer: *Tokenizer, token: Token) {
    tokenizer.recent_token_head = (tokenizer.recent_token_head + 1) % tokenizer.recent_tokens.count;
    tokenizer.recent_tokens[tokenizer.recent_token_head] = token;
}


Tokenizer :: struct {
    buf: string;
    max_t:   *u8;
    start_t: *u8;  // Cursor when starting parsing new token
    t:       *u8;  // Cursor

    return_eol := false;

    last_identifier_token: Token;
    recent_tokens: [64] Token;
    recent_token_head := 0;
    start_of_generic_index: int;
    angle_bracket_depth := 0;

    brace_depth: int;
    scope_stack: [64] Scope;

    Scope :: struct {
        flags: enum_flags {
            NONE :: 0;
            SAW_KEYWORD :: 1;
            SAW_MODIFIER_KEYWORD;
            SAW_JUMP_KEYWORD;
            SAW_TYPE;
            INFERRED_TYPE;
            SAW_IDENTIFIER;
            SAW_OPERATOR;
            SAW_PUNCTUATION;
            SAW_VALUE;
            SAW_DIRECTIVE;
        }

        state: enum {
            DEFAULT;
            IS_ATTRIBUTE;
            IS_DIRECTIVE;
            MAYBE_GENERIC;
        }
    }
}

Token :: struct {
    start, len: s32;
    type: Type;

    union {
        keyword:            Keyword;
        punctuation:        Punctuation;
        operation:          Operation;
        directive: Directive;
    }

    Type :: enum u16 {
        eof;
        eol;

        identifier;
        string_literal;
        char_literal;
        number;
        comment;
        multiline_comment;
        operation;
        punctuation;
        keyword;
        modifier_keyword;
        type_keyword;
        value_keyword;
        directive;
        invalid;
        jump_keyword;
        function_like;
        attribute;
    }

    as_string: string;
    color: Code_Color;
}


is_keyword :: (type: Token.Type) -> bool {
    return type == .keyword || type == .jump_keyword || type == .value_keyword || type == .modifier_keyword || type == .type_keyword;
}

is_keyword :: (token: *Token, keyword: Keyword) -> bool {
    return is_keyword(token.type) && token.keyword == keyword;
}

is_modifier :: (token: *Token, keyword: Keyword) -> bool {
    return token.type == .modifier_keyword && token.keyword == keyword;
}

is_punctuation :: (token: *Token, punctuation: Punctuation) -> bool {
    return token.type == .punctuation && token.punctuation == punctuation;
}

is_operation :: (token: *Token, operation: Operation) -> bool {
    return token.type == .operation && token.operation == operation;
}

is_directive :: (token: *Token, directive: Directive) -> bool {
    return token.type == .directive && token.directive == directive;
}


expect_token :: (offset := 0) -> *Token #expand {
    proc_name :: #procedure_name(#this);

    token, ok := peek_token(offset);
    if !ok  `return #run sprint("EOF in %", proc_name);
    return token;
}

eat_identifier :: () -> *Token #expand {
    proc_name :: #procedure_name(#this);

    token, ok := peek_token();
    if !ok  `return #run sprint("EOF in %", proc_name);

    if token.type != .identifier
        `return #run sprint("Expected identifier in %", proc_name);

    eat_token();
    return token;
}

eat_array_punctuation :: () -> is_array: bool #expand {
    proc_name :: #procedure_name(#this);

    token, ok := peek_token();
    if !ok  `return #run sprint("EOF in ", proc_name);

    if !is_punctuation(token, .l_bracket)
        return false;

    while true {
        eat_token();
        token, ok = peek_token();
        if !ok  `return #run sprint("EOF in ", proc_name);

        while is_punctuation(token, .comma) {
            eat_token();
            token, ok = peek_token();
            if !ok  `return #run sprint("EOF in ", proc_name);
        }

        `eat_punctuation(.r_bracket);

        token, ok := peek_token();
        if !ok  `return #run sprint("EOF in ", proc_name);

        if !is_punctuation(token, .l_bracket)
            return true;
    }

    return true;
}


eat_generic_identifier :: () -> *Token, is_generic: bool {
    result, result_ok := peek_token();
    if !result_ok || result.type != .identifier
        return null, false;

    paint_token(.type_keyword);

    eat_token();
    token, ok := peek_token();
    if !ok || token.type != .operation || token.operation != .less_than
        return result, false;

    eat_token();

    while true {
        identifier := eat_generic_identifier();
        if !identifier  return null, false;

        token, ok := peek_token();
        if !ok  return null, false;

        if is_operation(token, .greater_than) {
            eat_token();
            return result, true;
        }
        else if is_punctuation(token, .comma) {
            eat_token();
            continue;
        }

        return null, false;
    }
}

eat_punctuation :: (punctuation: Punctuation) -> *Token #expand {
    proc_name :: #procedure_name(#this);

    token, ok := peek_token();
    if !ok  `return #run sprint("EOF in %", proc_name);

    if !is_punctuation(token, punctuation)
        `return #run sprint("Expected % in %", punctuation, proc_name);

    eat_token();
    return token;
}

eat_operation :: (operation: Operation) -> *Token #expand {
    proc_name :: #procedure_name(#this);

    token, ok := peek_token();
    if !ok  `return #run sprint("EOF in %", proc_name);

    if !is_operation(token, operation)
        `return #run sprint("Expected % in %", operation, proc_name);

    eat_token();
    return token;
}


// Must match the order of the types in the enum above
COLOR_MAP :: Code_Color.[
    .COMMENT,       // eof - color unused
    .COMMENT,       // eol - color unused

    .DEFAULT,           // identifier
    .STRING,            // string_literal
    .STRING,            // char_literal
    .VALUE,             // number
    .COMMENT,           // comment
    .COMMENT,           // multiline_comment
    .OPERATION,         // operation
    .PUNCTUATION,       // punctuation
    .KEYWORD,           // keyword
    .MODIFIER_KEYWORD,  // modifier_keyword (currently no specific color available for modifiers)
    .TYPE,              // type_keyword
    .VALUE_KEYWORD,     // value_keyword
    .DIRECTIVE,         // directive
    .ERROR,             // invalid
    .JUMP_KEYWORD,      // jump keyword
    .FUNCTION,          // function-like
    .HIGHLIGHT,         // attribute
];

// https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/keywords
Keyword :: enum u16 {
    // Reserved identifiers
    kw_as;
    kw_base;
    kw_case;
    kw_checked;
    kw_class;
    kw_do;
    kw_else;
    kw_enum;
    kw_explicit;
    kw_fixed;
    kw_for;
    kw_foreach;
    kw_if;
    kw_implicit;
    kw_in; // Used in other contexts besides modifier
    kw_interface;
    kw_is;
    kw_lock;
    kw_namespace;
    kw_operator;
    kw_out; // Used in other contexts besides modifier
    kw_params;
    kw_ref;
    kw_sizeof;
    kw_stackalloc;
    kw_struct;
    kw_switch;
    kw_typeof;
    kw_unchecked;
    kw_while;

    kwj_break;
    kwj_catch;
    kwj_continue;
    kwj_finally;
    kwj_goto;
    kwj_return;
    kwj_throw;
    kwj_try;
    kwj_yield;

    kwv_default;
    kwv_false;
    kwv_null;
    kwv_this;
    kwv_true;
    kwv_value;

    kwm_abstract;
    kwm_async;
    kwm_delegate;
    kwm_const;
    kwm_event;
    kwm_extern;
    kwm_file;
    kwm_global;
    kwm_internal;
    kwm_new;
    kwm_override;
    kwm_private;
    kwm_protected;
    kwm_public;
    kwm_readonly;
    kwm_record;
    kwm_sealed;
    kwm_static;
    kwm_unsafe;
    kwm_virtual;
    kwm_volatile;

    kwt_bool;
    kwt_byte;
    kwt_char;
    kwt_decimal;
    kwt_double;
    kwt_float;
    kwt_int;
    kwt_long;
    kwt_object;
    kwt_sbyte;
    kwt_short;
    kwt_string;
    kwt_uint;
    kwt_ulong;
    kwt_ushort;
    kwt_void;
    // Type aliases
    // https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/builtin-types/built-in-types
    kwt_Boolean;
    kwt_Byte;
    kwt_Char;
    kwt_Decimal;
    kwt_Double;
    kwt_Single;
    kwt_Int32;
    kwt_Int64;
    kwt_Object;
    kwt_SByte;
    kwt_Int16;
    kwt_String;
    kwt_Uint32;
    kwt_UInt64;
    kwt_UInt16;
    kwt_Void;

    // Contextual keywords
    kw_add;
    kw_and;
    kw_alias;
    kw_ascending;
    kw_args;
    kw_await;
    kw_by;
    kw_descending;
    kw_dynamic;
    kw_equals;
    kw_file;
    kw_from;
    kw_group;
    kw_init;
    kw_into;
    kw_join;
    kw_let;
    kw_managed;
    kw_nameof;
    kw_not;
    kw_notnull;
    kw_on;
    kw_or;
    kw_orderby;
    kw_partial;
    kw_record;
    kw_remove;
    kw_required;
    kw_scoped;
    kw_select;
    kw_unmanaged;
    kw_using;
    kw_var;
    kw_when;
    kw_where;
    kw_with;

    kwt_nint;
    kwt_nuint;

    kwf_get;
    kwf_set;
}

Operation :: enum u16 {
    arrow;
    bang;
    pipe;
    double_pipe;
    pipe_equal;
    equal;
    equal_equal;
    bang_equal;
    percent;
    percent_equal;
    less_than;
    double_less_than;
    less_than_equal;
    greater_than;
    greater_than_equal;
    minus;
    minus_equal;
    minus_minus;
    asterisk;
    asterisk_equal;
    colon;
    slash;
    plus;
    plus_equal;
    plus_plus;
    slash_equal;
    ampersand;
    double_ampersand;
    ampersand_equal;
    tilde;
    question;
    caret;
    caret_equal;
}

is_assignment_operation :: (operation: Operation) -> bool {
    if operation == {
        case .equal; #through;
        case .pipe_equal; #through;
        case .percent_equal; #through;
        case .minus_equal; #through;
        case .asterisk_equal; #through;
        case .plus_equal; #through;
        case .slash_equal; #through;
        case .ampersand_equal; #through;
        case .caret_equal;
            return true;

        case;
            return false;
    }
}


Punctuation :: enum u16 {
    semicolon;
    backslash;
    l_paren;
    r_paren;
    l_brace;
    r_brace;
    l_bracket;
    r_bracket;
    period;
    comma;
}

// https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/preprocessor-directives
Directive :: enum u16 {
    di_nullable;
    di_if;
    di_elif;
    di_else;
    di_endif;
    di_define;
    di_pragma;
}

Keyword_Token :: struct {
    type: Token.Type;
    keyword: Keyword;
}


KEYWORD_MAP :: #run -> Table(string, Keyword_Token) {
    table: Table(string, Keyword_Token);
    init(*table, type_info(Keyword).values.count * size_of(Keyword));

    for enum_values_as_enum(Keyword) {
        name := enum_value_to_name(it);
        if starts_with(name, "kwt") {
            table_add(*table, slice(name, 4), .{.type_keyword, it});
        } else if starts_with(name, "kwm") {
            table_add(*table, slice(name, 4), .{.modifier_keyword, it});
        } else if starts_with(name, "kwv") {
            table_add(*table, slice(name, 4), .{.value_keyword, it});
        } else if starts_with(name, "kwj") {
            table_add(*table, slice(name, 4), .{.jump_keyword, it});
        } else if starts_with(name, "kwf") {
            table_add(*table, slice(name, 4), .{.function_like, it});
        } else {
            table_add(*table, slice(name, 3), .{.keyword, it});
        }
    }

    return table;
}

MAX_KEYWORD_LENGTH :: #run -> s32 {
    max: s64;
    prefix_count: s64;

    for enum_names(Keyword) {
        if starts_with(it, "kwt") prefix_count = 4;
        else if starts_with(it, "kwm") prefix_count = 4;
        else if starts_with(it, "kwv") prefix_count = 4;
        else prefix_count = 3;

        length := it.count - prefix_count;
        if length > max max = length;
    }

    return xx max;
}

PREPROCESSOR_DIRECTIVES_MAP :: #run -> Table(string, Directive) {
    table: Table(string, Directive);
    init(*table, type_info(Directive).values.count * size_of(Directive));

    for enum_values_as_enum(Directive) {
        name := enum_value_to_name(it);
        table_add(*table, slice(name, 3), it);
    }

    return table;
}

MAX_DIRECTIVE_LENGTH :: #run -> s32 {
    max: s64;

    for enum_names(Directive) {
        length := it.count - 3;
        if length > max max = length;
    }

    return xx max;
}

#run assert(type_info(Token.Type).values.count == COLOR_MAP.count);
