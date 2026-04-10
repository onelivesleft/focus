LOG_ERRORS :: false;

CSharp :: struct {
    filename: string;
    tokens: [..] CSToken;
    token_index: int;

    nodes: [..] CSNode;
    current_parent_node_index: int;
    attributes_to_assign: [..] int;
    current_flags: CSNode.Flags;
    current_type_token_index: int;

    in_property: bool;
}

break_on_name :: "sentinel";//"gunfire_fade_remainder";//"Start";
break_on_index :: 0;//971;
has_broken := false;


#add_context csharp: CSharp;


highlight_csharp_syntax :: (using buffer: *Buffer) {
    tokenizer := get_tokenizer(buffer);
    highlight_csharp_syntax(buffer, tokenizer);
}

highlight_csharp_syntax :: (using buffer: *Buffer, start_index: s32, count: s32) {
    tokenizer := New(CSTokenizer, initialized=false,, temp);
    tokenizer.* = .{
        buf        = cast(string) bytes,
        max_t      = bytes.data + start_index + count,
        t          = bytes.data + start_index,
    };
    add_recent_token(tokenizer, .{0, 0, "", .eof, .DEFAULT, 0});
    highlight_csharp_syntax(buffer, tokenizer);
}

highlight_csharp_syntax :: (using buffer: *Buffer, tokenizer: *CSTokenizer) {
    using context.csharp;

    #if LOG_ERRORS  print("% -------------------------------\n", frame_time);
    filename = buffer.file.name;

    tokenize_csharp(buffer, tokenizer);

    if tokens.count == 0  return;

    for * nodes  array_reset(*it.children);
    array_reset(*nodes);
    array_reset(*attributes_to_assign);
    root_node := array_add(*nodes);
    current_parent_node_index = 0;
    current_flags = .NONE;
    in_property = false;

    token_index = 0;

    lex_csharp();

    for tokens  memset(colors.data + it.start, xx it.color, it.len);
}


check :: (value: CSResult) -> bool {
    using context.csharp;

    if value.state == .ERROR {
        #if LOG_ERRORS {
            if token_index < tokens.count
                print("%: % @ % %\n", filename, value.error, tokens[token_index].start, tokens[token_index].as_string);
            else
                print("%: % (EOF)\n", filename, value.error);
        }
        return false;
    }
    else {
        return true;
    }
}

check_and_eat :: (value: *CSResult) -> bool {
    if !check(value.*)  return false;

    if value.state == .LEFT_TERMINATOR {
        eat_token();
        value.state = .ATE_TERMINATOR;
    }
    return true;
}


lex_csharp :: () {
    using context.csharp;

    while true {
        token := peek_token();
        if !token  break;

        error := "";

        start_token_index := token_index;

        if token.type == {
            case .keyword;
                if token.keyword == {
                    case .kw_using;
                        eat_token();
                        result := lex_using_directive_tail();
                        if check_and_eat(*result) {
                            paint_tokens(start_token_index, 1, .HIGHLIGHT);
                            // Make node
                            current_flags = .NONE;
                        }
                        continue;

                    case .kw_class;
                        paint_token(.MODIFIER_KEYWORD);
                        eat_token();
                        result := ifx current_flags & .RECORD then lex_record_class() else lex_class();
                        if check_and_eat(*result) {
                            // Make node
                            current_flags = .NONE;
                        }
                        continue;

                    case .kw_struct;
                        paint_token(.MODIFIER_KEYWORD);
                        eat_token();
                        result := lex_struct();
                        if check_and_eat(*result) {
                            // Make node
                            current_flags = .NONE;
                        }
                        continue;

                    case .kw_enum;
                        paint_token(.MODIFIER_KEYWORD);
                        eat_token();
                        result := lex_enum();
                        if check_and_eat(*result) {
                            // Make node
                            current_flags = .NONE;
                        }
                        continue;
                }

            case .punctuation;
                if token.punctuation == {
                    case .l_bracket;
                        eat_token();
                        result := lex_attribute_tail();
                        if check_and_eat(*result) {
                            array_add(*attributes_to_assign, nodes.count);
                            node := array_add(*nodes);
                            node.start_token_index = start_token_index;
                            node.end_token_index = token_index - 1;
                            node.type = .ATTRIBUTE;
                            current_flags |= .HAS_ATTRIBUTES;
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
                eat_token();
                result := lex_directive();
                check_and_eat(*result);
                continue;
        }

        eat_token();
    }
}


lex_directive :: () -> CSResult {
    token := expect_token();
    while token.type != .eol {
        if token.type == .identifier
            paint_token(.directive);
        eat_token();
        token = expect_token();
    }
    return .{.LEFT_TERMINATOR, ""};
}


lex_record_class :: () -> CSResult {
    // @TODO
    return .{};
}


lex_class :: #bake_arguments lex_class_or_struct(class_or_struct=.CLASS);
lex_struct :: #bake_arguments lex_class_or_struct(class_or_struct=.STRUCT);

lex_class_or_struct :: ($class_or_struct: enum {CLASS; STRUCT;}) -> CSResult {
    using context.csharp;

    identifier, is_generic := eat_generic(paint_as_type=true);
    if !identifier  return .{.ERROR, "Expected identifier in lex_class_or_struct"};

    token := expect_token();
    if is_operation(token, .colon) {
        eat_token();

        // Parent class + interfaces
        eat_generic(accept_type=true, paint_as_type=true);
        token = expect_token();
        while is_punctuation(token, .comma) {
            eat_token();
            eat_generic(accept_type=true, paint_as_type=true);
            token = expect_token();
        }
    }

    while is_generic && is_keyword(token, .kw_where) {
        eat_token();
        maybe_convert_keyword_to_identifier();
        eat_identifier();
        eat_operation(.colon);

        eat_generic(accept_type=true, paint_as_type=true);
        token = expect_token();
        while is_punctuation(token, .comma) {
            eat_token();
            eat_generic(accept_type=true, paint_as_type=true);
            token = expect_token();
        }
    }

    eat_punctuation(.l_brace);

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

            case .keyword;
                if token.keyword == {
                    case .kw_enum;
                        eat_token();
                        result := lex_enum();
                        check_and_eat(*result);
                        current_flags = .NONE;
                        continue;

                    case .kw_struct;
                        eat_token();
                        result := lex_struct();
                        check_and_eat(*result);
                        current_flags = .NONE;
                        continue;

                    case .kw_class;
                        eat_token();
                        result := lex_class();
                        check_and_eat(*result);
                        current_flags = .NONE;
                        continue;
                }

            case .identifier;
                paint_token(.type_keyword);
                #through;

            case .type_keyword;
                current_type_token_index = token_index;
                identifier, is_generic := eat_generic(accept_type=true, paint_as_type=true);
                maybe_eat_nullable(identifier);
                token = expect_token();
                if is_punctuation(token, .l_paren) {
                    eat_token();
                    result := lex_function_declaration(is_generic, current_flags & .DELEGATE != 0);
                    check_and_eat(*result);
                }
                else {
                    result := lex_declaration();
                    check_and_eat(*result);
                }
                current_flags = .NONE;
                continue;

            case .punctuation;
                if token.punctuation == {
                    case .r_brace;
                        eat_token();
                        return .{.ATE_TERMINATOR, ""};

                    case .l_bracket;
                        eat_token();
                        result := lex_attribute_tail();
                        if check_and_eat(*result) {
                            array_add(*attributes_to_assign, nodes.count);
                            node := array_add(*nodes);
                            node.start_token_index = start_token_index;
                            node.end_token_index = token_index - 1;
                            node.type = .ATTRIBUTE;
                            current_flags |= .HAS_ATTRIBUTES;
                        }
                        continue;
                }
        }

        eat_token();
    }

    return .{}; // unreachable
}


lex_enum :: () -> CSResult {
    using context.csharp;

    identifier, is_generic := eat_generic(paint_as_type=true);
    if !identifier  return .{.ERROR, "Expected identifier in lex_class"};

    token := expect_token();
    if is_operation(token, .colon) {
        eat_token();
        eat_generic(accept_type=true, paint_as_type=true);
    }

    eat_punctuation(.l_brace);

    token = expect_token();
    while true {
        while is_punctuation(token, .comma) {
            eat_token();
            token = expect_token();
        }

        if is_punctuation(token, .r_brace)
            return .{.LEFT_TERMINATOR, ""};

        eat_identifier();

        token = expect_token();
        if is_operation(token, .equal) {
            eat_token();
            token = eat_until_punctuation(.comma, .r_brace);
        }
    }

    return .{}; // unreachable
}


Scope_Mode :: enum {
    BRACED;
    STATEMENT;
    FOR_STATEMENT;
    NEW_BRACED_BLOCK;
}


terminators_for_mode :: (mode: Scope_Mode) -> Punctuation, Punctuation {
    if #complete mode == {
        case .BRACED;  #through;
        case .STATEMENT;
            return .semicolon, NO_PUNCTUATION();

        case .FOR_STATEMENT;
            return .r_paren, .comma;

        case .NEW_BRACED_BLOCK;
            return .r_brace, .comma;
    }
}


lex_body :: (mode: Scope_Mode, terminator1 := Punctuation.r_brace, terminator2 : Punctuation = 65535) -> CSResult {
    // lex_body should *always* return .ERROR or .LEFT_TERMINATOR!!!

    using context.csharp;

    current_flags = .NONE;

    if mode == .STATEMENT {
        token := expect_token();
        if token.type == .keyword {
            result := lex_keyword(mode, token);
            if result.state == .ATE_TERMINATOR {
                token_index -= 1;
                result.state = .LEFT_TERMINATOR;
            }
            return result;
        }
    }

    while true {
        start_token_index := token_index;

        token := expect_token();
        if #complete token.type == {
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


            case .type_keyword;
                current_type_token_index = token_index;
                eat_token();
                maybe_eat_nullable(*tokens[current_type_token_index]);
                result := lex_declaration();
                if !check(result)  return result;
                assert(result.state == .LEFT_TERMINATOR);
                if mode == .STATEMENT
                    return result;
                eat_token();
                current_flags = .NONE;

            case .identifier;
                token = eat_generic();
                t1, t2 := terminators_for_mode(mode);
                result := lex_body_lhs_identifier(token, t1, t2);
                if !check(result)  return result;
                assert(result.state == .LEFT_TERMINATOR);
                if mode == .STATEMENT || mode == .FOR_STATEMENT
                    return result;
                eat_token();
                current_flags = .NONE;

            case .jump_keyword;
                if token.keyword == .kwj_return {
                    eat_token();
                    result := lex_expression(.semicolon);
                    if !check(result)  return result;
                    if mode == .STATEMENT {
                        assert(result.state == .LEFT_TERMINATOR);
                        return result;
                    }
                    eat_token();
                }
                else {
                    eat_token();
                }

            case .keyword;
                current_flags = .NONE;
                result := lex_keyword(mode, token);
                if !check_and_eat(*result)  return result;

            case .value_keyword; #through;
            case .string_literal; #through;
            case .char_literal; #through;
            case .number; #through;
            case .comment; #through;
            case .multiline_comment; #through;
            case .function; #through;
            case .operation; #through;
            case .modifier_keyword; #through;
            case .invalid; #through;
            case .eof; #through;
            case .eol; #through;
            case .attribute;
                eat_token();


            case .punctuation;
                if token.punctuation == terminator1 || token.punctuation == terminator2
                    return .{.LEFT_TERMINATOR, ""};

                if token.punctuation == {
                    case .l_paren;
                        eat_token();
                        result := lex_expression(.r_paren);
                        if !check(result)  return result;
                        eat_token();

                    case .l_brace;
                        eat_token();
                        result := lex_body(.BRACED);
                        if !check(result)  return result;
                        eat_token();

                    case .l_bracket;
                        eat_token();
                        result := lex_attribute_tail();
                        if check(result) {
                            array_add(*attributes_to_assign, nodes.count);
                            node := array_add(*nodes);
                            node.start_token_index = start_token_index;
                            node.end_token_index = token_index - 1;
                            node.type = .ATTRIBUTE;
                            current_flags |= .HAS_ATTRIBUTES;
                        }
                        eat_token();

                    case;
                        eat_token();
                }
        }
    }

    return .{};
}


lex_keyword :: (mode: Scope_Mode, token: *CSToken) -> CSResult {
    assert(token.type == .keyword);

    if token.keyword == {
        case .kw_case;
            eat_token();
            token := expect_token();
            if token.type == .identifier || token.type == .type_keyword
                eat_generic();
            else
                eat_token();
            eat_operation(.colon);

        case .kw_default;
            eat_token();
            eat_operation(.colon);

        case .kw_do;
            eat_token();
            token = expect_token();
            if is_punctuation(token, .l_brace) {
                eat_token();
                result := lex_body(.BRACED);
                if !check(result)  return result;
                assert(result.state == .LEFT_TERMINATOR);
                eat_punctuation(.r_brace);
            }
            else {
                eat_token();
                result := lex_body(.STATEMENT, .semicolon);
                if !check(result)  return result;
                if mode == .STATEMENT {
                    assert(result.state == .LEFT_TERMINATOR);
                    return result;
                }
                eat_token();
            }
            token = expect_token();
            if is_keyword(token, .kw_while) {
                eat_token();
                token = expect_token();
                if is_punctuation(token, .l_paren) {
                    eat_token();
                    result := lex_expression(.r_paren);
                    if !check(result)  return result;
                    if mode == .STATEMENT {
                        assert(result.state == .LEFT_TERMINATOR);
                        return result;
                    }
                    eat_token();
                }
                else {
                    return .{.ERROR, "Expected ( in do while"};
                }
            }

        case .kw_if; #through;
        case .kw_switch; #through;
        case .kw_while;
            eat_token();
            eat_punctuation(.l_paren);
            result := lex_expression(.r_paren);
            if !check_and_eat(*result)
                return result;
            token = expect_token();
            if is_punctuation(token, .l_brace) {
                eat_token();
                result = lex_body(.BRACED);
                if !check(result)  return result;
                assert(result.state == .LEFT_TERMINATOR);
                eat_punctuation(.r_brace);
            }
            else {
                result = lex_body(.STATEMENT, .semicolon);
                if !check(result)  return result;
                if mode == .STATEMENT {
                    assert(result.state == .LEFT_TERMINATOR);
                    return result;
                }
                eat_token();
            }

        case .kw_else;
            eat_token();
            token = expect_token();
            if is_punctuation(token, .l_brace) {
                eat_token();
                result := lex_body(.BRACED);
                if !check(result)  return result;
                assert(result.state == .LEFT_TERMINATOR);
                eat_punctuation(.r_brace);
            }
            else if token.type == .keyword {
                // Don't do anything, just let the loop go round
            }
            else {
                result := lex_body(.STATEMENT, .semicolon);
                if !check(result)  return result;
                if mode == .STATEMENT {
                    assert(result.state == .LEFT_TERMINATOR);
                    return result;
                }
                eat_token();
            }

        case .kw_for;
            eat_token();
            eat_punctuation(.l_paren);

            eat_generic(accept_type=true, paint_as_type=true);
            while true {
                result := lex_assignment();
                if !check(result)  return result;
                token = expect_token();
                eat_token();
                if is_punctuation(token, .semicolon)
                    break;
                assert(is_punctuation(token, .comma), "lex_assigment should only error or stop on .semicolon or .comma");
            }

            result := lex_expression(.semicolon);
            if !check_and_eat(*result)  return result;

            while true {
                result = lex_body(.FOR_STATEMENT, .r_paren, .comma);
                if !check(result)  return result;
                assert(result.state == .LEFT_TERMINATOR);
                token = expect_token();
                eat_token();
                if is_punctuation(token, .r_paren)
                    break;
                assert(is_punctuation(token, .comma), "lex_body should only error or stop on .r_paren or .comma");
            }

            token = expect_token();
            if is_punctuation(token, .l_brace) {
                eat_token();
                result = lex_body(.BRACED);
                if !check(result)  return result;
                assert(result.state == .LEFT_TERMINATOR);
                eat_punctuation(.r_brace);
            }
            else {
                result = lex_body(.STATEMENT, .semicolon);
                if !check(result)  return result;
                if mode == .STATEMENT {
                    assert(result.state == .LEFT_TERMINATOR);
                    return result;
                }
                eat_token();
            }

        case .kw_foreach;
            eat_token();
            eat_punctuation(.l_paren);
            eat_generic(accept_type=true, paint_as_type=true);
            eat_identifier();
            eat_keyword(.kwm_in);
            paint_last_token(.keyword);

            result := lex_expression(.r_paren);
            if !check(result)  return result;

            eat_token();
            token = expect_token();
            if is_punctuation(token, .l_brace) {
                eat_token();
                result = lex_body(.BRACED);
                if !check(result)  return result;
                assert(result.state == .LEFT_TERMINATOR);
                eat_punctuation(.r_brace);
            }
            else {
                result = lex_body(.STATEMENT, .semicolon);
                if !check(result)  return result;
                if mode == .STATEMENT {
                    assert(result.state == .LEFT_TERMINATOR);
                    return result;
                }
                eat_token();
            }

        case;
            eat_token();
    }

    return .{.ATE_TERMINATOR, ""};
}


maybe_eat_nullable :: (type_token_to_mark: *CSToken) {
    token := peek_token();
    if token && is_operation(token, .question) {
        // @TODO mark token as nullable
        eat_token();
    }
}


maybe_convert_keyword_to_identifier :: (token : *CSToken = null) {
    // Maybe the user has used a keyword as a name (which is potentially legal), so just treat it as such
    if !token  token = peek_token();
    if token && (is_keyword(token.type) || token.type == .function)
        paint_token(token, .identifier);
}


maybe_eat_array_index :: () -> existed: bool #expand #no_debug {
    token := `expect_token();
    existed := false;
    while is_punctuation(token, .l_bracket) {
        existed = true;
        eat_token();
        while true {
            result := lex_expression(.r_bracket, .comma);
            if !check(result)  `return result;
            token = `expect_token();
            eat_token();
            if !is_punctuation(token, .comma) {
                assert(is_punctuation(token, .r_bracket), "lex_expression should have errored or returned .r_bracket or .comma");
                break;
            }
        }
        token = `expect_token();
    }
    return existed;
}


lex_body_lhs_identifier :: (identifier: *CSToken, terminator1: Punctuation, terminator2: Punctuation, first_token_index := -1) -> CSResult {
    using context.csharp;

    if first_token_index < 0  first_token_index = token_index - 1;

    token := expect_token();
    while is_punctuation(token, .l_paren) { // is a function call
        paint_identifier(identifier, .function);
        eat_token();
        result := lex_function_call_tail();
        if !check(result)  return result;
        assert(result.state == .ATE_TERMINATOR);

        token = expect_token();
    }

    if maybe_eat_array_index()
        token = expect_token();

    if is_punctuation(token, .period) {
        eat_token();
        identifier = eat_generic();
        return lex_body_lhs_identifier(identifier, terminator1, terminator2, first_token_index);
    }

    maybe_convert_keyword_to_identifier(token);

    if token.type == .identifier {
        paint_identifiers(first_token_index, token_index, .type_keyword);
        identifier = eat_generic();
        assert(identifier != null);
        return lex_body_lhs_identifier(identifier, terminator1, terminator2, first_token_index);
    }

    if token.type == .operation {
        if !is_assignment_operation(token.operation) && !is_modify_in_place_operation(token.operation)
            return .{.ERROR, "Unexpected operation on lhs"};

        eat_token();
        token = expect_token();
        if is_keyword(token, .kwm_new) {
            paint_token(.function);
            eat_token();
            result := lex_expression_new();
            if !check(result)  return result;
            assert(result.state == .ATE_TERMINATOR);
        }
        else {
            result := lex_expression(terminator1, terminator2);
            if !check(result)  return result;
            assert(result.state == .LEFT_TERMINATOR);
        }
        token = expect_token();
    }

    return lex_expression(terminator1, terminator2);
}


lex_expression_identifier :: (name: *CSToken) -> CSResult {
    using context.csharp;

    if !name  return .{.ERROR, "Expected identifier"};

    token := expect_token();
    while is_punctuation(token, .l_paren) {
        paint_identifier(name, .function);
        eat_token();
        result := lex_function_call_tail();
        if !check_and_eat(*result)  return result;

        token = expect_token();
    }

    if maybe_eat_array_index()
        token = expect_token();

    if is_punctuation(token, .period) {
        eat_token();
        after_dot := eat_generic();
        return lex_expression_identifier(after_dot);
    }

    return .{.ATE_TERMINATOR, ""};
}


lex_declaration :: () -> CSResult {
    using context.csharp;

    if eat_array_punctuation()  current_flags |= .IS_ARRAY;

    name_identifier: *CSToken;
    is_generic := false;

    token := expect_token();
    if token.type == .keyword {
        if token.keyword == .kw_operator {
            paint_token(.function);
            eat_token();
            token = expect_token();
            if token.type != .operation
                return .{.ERROR, "Expected operator"};
            paint_token(.function);
            eat_token();
        }
        else {
            maybe_convert_keyword_to_identifier();
            name_identifier, is_generic = eat_generic();
        }
    }
    else {
        maybe_convert_keyword_to_identifier();
        name_identifier, is_generic = eat_generic();
    }

    token = expect_token();
    if token.type == {
        case .punctuation;
            if token.punctuation == {
                case .semicolon;
                    return .{.LEFT_TERMINATOR, ""};

                case .comma;
                    eat_token();
                    return lex_declaration();

                case .l_paren;
                    if name_identifier  paint_token(name_identifier, .function);
                    eat_token();
                    return lex_function_declaration(is_generic, current_flags & (.ABSTRACT|.DELEGATE|.EXTERN) != 0);

                case .l_brace;
                    eat_token();
                    return lex_property();
            }

        case .operation;
            if token.operation == .equal {
                eat_token();
                result := lex_assignment_rhs(.semicolon, .comma);
                if !check(result)  return result;
                token := expect_token();
                if is_punctuation(token, .comma) {
                    eat_token();
                    return lex_declaration();
                }
                return .{.LEFT_TERMINATOR, ""};
            }
    }

    return .{.ERROR, "Unexpected token in lex_declaration"};
}


lex_function_declaration :: (is_generic: bool, is_stub: bool) -> CSResult {
    using context.csharp;

    result := lex_function_declaration_tail(is_generic);
    if !check(result)  return result;

    if !is_stub {
        eat_punctuation(.l_brace);
        return lex_body(.BRACED);
    }
    else {
        token := expect_token();
        if !is_punctuation(token, .semicolon)
            return .{.ERROR, "Expected delegate to end with ;"};
        return .{.LEFT_TERMINATOR, ""};
    }
}


lex_function_declaration_tail :: (is_generic: bool) -> CSResult {
    using context.csharp;

    assert(is_punctuation(peek_token(-1), .l_paren));

    token := expect_token();
    if is_punctuation(token, .r_paren) {
        eat_token();
        return .{.ATE_TERMINATOR, ""};
    }

    while true {
        while token.type == .modifier_keyword || is_keyword(token, .kwv_this) {
            eat_token();
            token = expect_token();
        }

        if token.type != .identifier && token.type != .type_keyword
            return .{.ERROR, "Expected parameter type in function signature"};

        type_identifier := eat_generic(accept_type=true, paint_as_type=true);
        maybe_eat_array_index();

        token = expect_token();
        maybe_convert_keyword_to_identifier(token);
        if token.type != .identifier
            return .{.ERROR, "Expected parameter name in function signature"};

        eat_token();
        token = expect_token();
        if is_operation(token, .equal) {
            eat_token();
            result := lex_expression(.r_paren, .comma);
            if !check(result)  return result;
            assert(result.state == .LEFT_TERMINATOR);
            token = expect_token();
        }

        if token.type != .punctuation
            return .{.ERROR, "Expected , ) in function signature"};

        if token.punctuation == {
            case .r_paren;
                eat_token();
                break;

            case .comma;
                eat_token();
                token = expect_token();

            case;
                return .{.ERROR, "Expected , ) in function signature"};
        }
    }

    token = expect_token();

    while is_generic && is_keyword(token, .kw_where) {
        eat_token();
        start_token_index := token_index;
        eat_identifier();
        eat_operation(.colon);

        maybe_convert_keyword_to_identifier();
        eat_generic(accept_type=true, paint_as_type=true);
        token = expect_token();
        while is_punctuation(token, .comma) {
            eat_token();
            eat_generic(accept_type=true, paint_as_type=true);
            token = expect_token();
        }

        paint_identifiers(start_token_index, token_index, .type_keyword);
    }

    return .{.ATE_TERMINATOR, ""};
}


lex_function_call_tail :: () -> CSResult {
    using context.csharp;

    assert(is_punctuation(peek_token(-1), .l_paren));

    while true {
        token := expect_token();
        while token.type == .modifier_keyword {
            if token.keyword == .kwm_new {
                paint_token(token, .function);
                eat_token();
                result := lex_expression_new();
                if !check(result)  return result;
                assert(result.state == .ATE_TERMINATOR);
            }
            else {
                eat_token();
            }
            token = expect_token();
        }

        parameter_name := token;
        if parameter_name.type == .identifier {
            colon := expect_token(+1);
            if is_operation(colon, .colon)
                eat_tokens(2);
        }

        result := lex_expression(.r_paren, .comma);
        if !check(result)  return result;

        comma_or_paren := expect_token();
        assert(comma_or_paren.type == .punctuation);
        if comma_or_paren.punctuation == {
            case .r_paren;
                eat_token();
                return .{.ATE_TERMINATOR, ""};

            case .comma;
                eat_token();

            case;
                assert(false);
        }
    }

    return .{}; // Unreachable
}


lex_property :: () -> CSResult {
    using context.csharp;

    in_property = true;
    defer in_property = false;

    token := expect_token();
    while !is_punctuation(token, .r_brace) {
        if token.type != .function || (token.keyword != .kwf_get && token.keyword != .kwf_set)
            return .{.ERROR, "Expected get or set in property"};
        eat_token();
        token = expect_token();
        if is_punctuation(token, .l_brace) {
            eat_token();
            result := lex_body(.BRACED);
            if !check(result)  return result;
            eat_token();
        }
        else if is_operation(token, .equal_greater_than) {
            eat_token();
            result := lex_expression(.semicolon);
            if !check(result)  return result;
            eat_token();
        }
        else {
            return .{.ERROR, "Unexpected token in property"};
        }

        token = expect_token();
    }

    return .{.LEFT_TERMINATOR, ""};
}


lex_using_directive_tail :: () -> CSResult {
    using context.csharp;

    token := expect_token();

    if is_modifier(token, .kwm_static) {
        current_flags |= .STATIC;
        token = expect_token();
    }

    result := lex_identifier_dot_chain();
    if !check(result)  return result;

    token = expect_token();
    if is_operation(token, .equal) {
        eat_token();
        result := lex_identifier_dot_chain();
        if !check(*result)  return result;

    }

    return .{.ATE_TERMINATOR, ""};
}


lex_identifier_dot_chain :: () -> CSResult {
    while true {
        maybe_convert_keyword_to_identifier();
        eat_identifier();

        token := expect_token();
        if !is_punctuation(token, .period)
            return .{.ATE_TERMINATOR, ""};
        eat_token();
    }

    return .{}; // unreachable
}


lex_attribute_tail :: () -> CSResult {
    using context.csharp;

    first_token := expect_token();
    second_token := expect_token(+1);
    if is_operation(second_token, .colon) && (first_token.type == .identifier || is_keyword(first_token, .kwj_return) || is_keyword(first_token, .kwm_event)) {
        // Attribute target specifier
        paint_token(.attribute, .HIGHLIGHT);
        eat_token();
        eat_token();
    }

    token := expect_token();
    lex_identifier_dot_chain();
    paint_identifier(token, .attribute, .HIGHLIGHT);
    expect_paren_or_bracket := expect_token();

    if expect_paren_or_bracket.type == .punctuation {
        if expect_paren_or_bracket.punctuation == .r_bracket {
            // [attribute]
            eat_token();
            return .{.ATE_TERMINATOR, ""};
        }
        else if expect_paren_or_bracket.punctuation == .l_paren {
            // [attribute(positional_parameters, name_parameter = value)]
            result := lex_attribute_call();
            if !check(result)  return result;

            token := eat_punctuation(.r_bracket);
            token.type = .attribute;
            token.color = .HIGHLIGHT;
            return .{.ATE_TERMINATOR, ""};
        }
    }

    return .{.ERROR, "Unexpected token in Attribute"};
}


lex_attribute_call :: () -> CSResult {
    using context.csharp;

    eat_punctuation(.l_paren);

    while true {
        is_named_parameter := false;
        parameter_name := expect_token();
        if parameter_name.type == .identifier {
            maybe_equals := expect_token(1);
            is_named_parameter = is_operation(maybe_equals, .equal);
        }

        if is_named_parameter  eat_tokens(2);

        result := ifx is_named_parameter
                 then lex_attribute_assignment(parameter_name)
                 else lex_expression(.r_paren, .comma);
        if !check(result)  return result;
        assert(result.state == .LEFT_TERMINATOR);

        comma_or_paren := expect_token();
        if comma_or_paren.punctuation == {
            case .r_paren;
                eat_token();
                return .{.ATE_TERMINATOR, ""};

            case .comma;
                eat_token();
        }
    }

    return .{}; // Unreachable
}


lex_attribute_assignment :: (identifier : *CSToken = null) -> CSResult {
    if !identifier {
        identifier = eat_identifier();
        eat_operation(.equal);
    }
    else {
        assert(peek_token(-2).type == .identifier);
        assert(is_operation(peek_token(-1), .equal));
    }

    return lex_expression(.r_paren, .comma);
}


lex_assignment :: () -> CSResult {
    eat_identifier();
    eat_operation(.equal);
    return lex_assignment_rhs(.semicolon, .comma);
}


maybe_eat_cast :: () -> CSResult {
    assert(is_punctuation(expect_token(), .l_paren));
    eat_token();
    eat_generic(); // Don't paint here, as we might not be a cast and don't want to change anything until we're sure we are.
    eat_punctuation(.r_paren);
    return .{.ATE_TERMINATOR, ""};
}


lex_assignment_rhs :: (terminator1: Punctuation, terminator2 : Punctuation = cast(Punctuation) 65535) -> CSResult {
    using context.csharp;

    token := expect_token();

    if is_punctuation(token, .l_brace) {
        eat_token();
        return lex_initializer_body();
    }
    else if is_keyword(token, .kwm_new) {
        paint_token(.function);
        eat_token();
        result := lex_expression_new();
        if !check(result)  return result;
        assert(result.state == .ATE_TERMINATOR);
        token_index -= 1;
        result.state = .LEFT_TERMINATOR;
        return result;
    }
    else {
        return lex_expression(terminator1, terminator2);
    }
}


lex_expression :: (terminator1: Punctuation, terminator2 : Punctuation = cast(Punctuation) 65535) -> CSResult {
    using context.csharp;

    token := expect_token();

    while true {
        if #complete token.type == {
            case .invalid;
                eat_token();
                return .{.ERROR, "Invalid token in expression"};

            case .punctuation;
                if token.punctuation == terminator1 || token.punctuation == terminator2
                    return .{.LEFT_TERMINATOR, ""};

                if #complete token.punctuation == {
                    case .l_paren;
                        index := token_index;
                        result := maybe_eat_cast();
                        if result.state == .ERROR { // not a cast
                            token_index = index + 1;
                            result = lex_expression(.r_paren);
                            if !check(result)  return result;
                            assert(result.state == .LEFT_TERMINATOR);
                            eat_token();
                        }
                        else {
                            paint_identifiers(index, token_index, .type_keyword);
                        }

                    case .l_brace;
                        eat_token();
                        result := lex_body(.BRACED);
                        if !check(result)  return result;
                        eat_token();

                    case .l_bracket;
                        maybe_eat_array_index();

                    case .period;
                        eat_token();

                    case .semicolon;
                        return .{.ERROR, "Unexpected ; in expression"};

                    case .comma;
                        //return .{.ERROR, "Unexpected , in expression"};
                        // Could be in a lambda declaration, so allow it
                        eat_token();

                    case .backslash;
                        return .{.ERROR, "Unexpected \\ in expression"};

                    case .r_paren;
                        return .{.ERROR, "Unexpected ) in expression"};

                    case .r_brace;
                        return .{.ERROR, "Unexpected } in expression"};

                    case .r_bracket;
                        return .{.ERROR, "Unexpected ] in expression"};
                }

            case .operation;
                eat_token();

            case .keyword;
                if token.keyword == {
                    case .kw_sizeof; #through;
                    case .kw_typeof;
                        eat_token();

                    case; // Maybe the user has used a keyword as a name (which is potentially legal), so just treat it as such
                        paint_token(.identifier);
                        name := eat_generic();
                        result := lex_expression_identifier(name);
                        if !check(result)  return result;
                }

            case .value_keyword; #through;
            case .type_keyword; #through;
            case .string_literal; #through;
            case .char_literal; #through;
            case .number; #through;
            case .multiline_comment; #through;
            case .function; #through;
            case .attribute;
                eat_token();

            case .identifier;
                name := eat_generic();
                result := lex_expression_identifier(name);
                if !check(result)  return result;

            case .comment;
                return .{.ERROR, "Unexpected // in expression"};

            case .modifier_keyword;
                if token.keyword == .kwm_new {
                    paint_token(.function);
                    eat_token();
                    result := lex_expression_new();
                    if !check(result)  return result;
                    assert(result.state == .ATE_TERMINATOR);
                }
                else {
                    return .{.ERROR, "Unexpected modifier keyword in expression"};
                }

            case .jump_keyword;
                return .{.ERROR, "Unexpected jump keyword in expression"};

            case .directive;
                return .{.ERROR, "Unexpected directive in expression"};

            case .eof;
                return .{.ERROR, "Unexpected EOF in expression"};

            case .eol;
                return .{.ERROR, "Unexpected EOL in expression"};
        }

        token = expect_token();
    }

    return .{}; // unreachable
}


lex_expression_new :: () -> CSResult {
    token := expect_token();
    is_array := false;
    if token.type == .identifier || token.type == .type_keyword {
        eat_generic(accept_type=true, paint_as_type=true);
        is_array = maybe_eat_array_index();
    }

    if is_array {
        token = expect_token();
        if is_punctuation(token, .l_brace) {
            eat_token();
            result := lex_initializer_body();
            if !check(result)  return result;
            assert(result.state == .ATE_TERMINATOR);
        }
    }
    else {
        token = expect_token();
        if is_punctuation(token, .l_brace) {
            eat_token();
            result := lex_initializer_body();
            if !check(result)  return result;
            assert(result.state == .ATE_TERMINATOR);
        }
        else {
            eat_punctuation(.l_paren);

            token = expect_token();
            if is_punctuation(token, .r_paren) {
                eat_token();
                token = expect_token();
                if is_punctuation(token, .l_brace) {
                    eat_token();
                    result := lex_initializer_body();
                    if !check(result)  return result;
                    assert(result.state == .ATE_TERMINATOR);
                }
            }
            else {
                result := lex_function_call_tail();
                if !check(result)  return result;
                assert(result.state == .ATE_TERMINATOR);
            }
        }
    }

    return .{.ATE_TERMINATOR, ""};
}


lex_initializer_body :: () -> CSResult {
    using context.csharp;

    while true {
        token := expect_token();
        if is_keyword(token, .kwm_new) {
            paint_token(.function);
            eat_token();
            result := lex_expression_new();
            if !check(result)  return result;
            assert(result.state == .ATE_TERMINATOR);
        }
        else {
            is_named_parameter := false;
            parameter_name := expect_token();
            if parameter_name.type == .identifier {
                maybe_equals := expect_token(1);
                is_named_parameter = is_operation(maybe_equals, .equal);
            }

            if is_named_parameter  eat_tokens(2);

            result := ifx is_named_parameter
                     then lex_initializer_assignment(parameter_name)
                     else lex_expression(.r_brace, .comma);
            if !check(result)  return result;
            assert(result.state == .LEFT_TERMINATOR);
        }

        comma_or_brace := expect_token();
        if comma_or_brace.punctuation == {
            case .r_brace;
                eat_token();
                return .{.ATE_TERMINATOR, ""};

            case .comma;
                eat_token();
        }
    }

    return .{}; // Unreachable
}


lex_initializer_assignment :: (identifier : *CSToken = null) -> CSResult {
    if !identifier {
        identifier = eat_identifier();
        eat_operation(.equal);
    }
    else {
        assert(peek_token(-2).type == .identifier);
        assert(is_operation(peek_token(-1), .equal));
    }

    return lex_expression(.r_brace, .comma);
}

paint_identifier :: (token: *CSToken, type: CSToken.Type, color: Code_Color) {
    using context.csharp;

    assert(token.type == .identifier || token.type == .type_keyword);

    if token.attached_up_to_index
        paint_identifiers(index_from_pointer(token), token.attached_up_to_index, type, color);
    else
        paint_token(token, type, color);
}

paint_identifier :: (token: *CSToken, type: CSToken.Type) {
    inline paint_identifier(token, type, COLOR_MAP[type]);
}

paint_identifiers :: (start_index: int, stop_before: int, type: CSToken.Type, color: Code_Color) {
    using context.csharp;

    for start_index .. stop_before - 1 {
        token := *tokens[it];
        if token.type == .identifier || token.type == .type_keyword {
            token.type = type;
            token.color = color;
        }
    }
}

paint_identifiers :: (start_index: int, stop_before: int, type: CSToken.Type) {
    inline paint_identifiers(start_index, stop_before, type, COLOR_MAP[type]);
}

paint_tokens :: (start_index: int, count: int, type: CSToken.Type, color: Code_Color) {
    using context.csharp;

    for 0 .. count - 1 {
        token := *tokens[start_index + it];
        token.type = type;
        token.color = color;
    }
}

paint_tokens :: (start_index: int, count: int, type: CSToken.Type) {
    inline paint_tokens(start_index, count, type, COLOR_MAP[type]);
}

paint_tokens :: (start_index: int, count: int, color: Code_Color) {
    using context.csharp;

    for 0 .. count - 1 {
        token := *tokens[start_index + it];
        token.color = color;
    }
}

paint_token :: (token: *CSToken, type: CSToken.Type, color: Code_Color) {
    token.type = type;
    token.color = color;
}

paint_token :: (token: *CSToken, type: CSToken.Type) {
    inline paint_token(token, type, COLOR_MAP[type]);
}

paint_token :: (token: *CSToken, color: Code_Color) {
    token.color = color;
}


paint_token :: (type: CSToken.Type, color: Code_Color) {
    using context.csharp;
    token := *tokens[token_index];
    token.type = type;
    token.color = color;
}

paint_token :: (type: CSToken.Type) {
    inline paint_token(type, COLOR_MAP[type]);
}

paint_token :: (color: Code_Color) {
    using context.csharp;
    token := *tokens[token_index];
    token.color = color;
}


paint_last_token :: (type: CSToken.Type, color: Code_Color) {
    using context.csharp;
    token := *tokens[token_index - 1];
    token.type = type;
    token.color = color;
}

paint_last_token :: (type: CSToken.Type) {
    inline paint_last_token(type, COLOR_MAP[type]);
}

paint_last_token :: (color: Code_Color) {
    using context.csharp;
    token := *tokens[token_index - 1];
    token.color = color;
}


peek_token :: (offset := 0) -> *CSToken {
    using context.csharp;

    #if break_on_name {
        if !has_broken && token_index + offset < tokens.count {
            if tokens[token_index + offset].as_string == break_on_name {
                has_broken = true;
                #asm {int3;}
            }
        }
    }

    #if break_on_index {
        if !has_broken && token_index + offset == break_on_index {
            has_broken = true;
            #asm {int3;}
        }
    }

    if token_index + offset < tokens.count {
        token := *tokens[token_index + offset];
        if in_property && token.type == .identifier && token.as_string == "value" && !is_punctuation(*tokens[token_index + offset - 1], .period)
            paint_token(token, .value_keyword);
        return token;
    }
    else
        return null;
}


eat_token :: () -> eof: bool {
    using context.csharp;
    token_index += 1;
    return token_index >= tokens.count;
}


eat_tokens :: (count: int) -> eof: bool {
    using context.csharp;
    token_index += count;
    return token_index >= tokens.count;
}


#scope_module


tokenize_csharp :: (using buffer: *Buffer, tokenizer: *CSTokenizer) {
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
        EXPLICIT;
        EXTERN;
        FILE;
        GLOBAL;
        IMPLICIT;
        IN;
        INTERNAL;
        NEW;
        OUT;
        OVERRIDE;
        PARAMS;
        PRIVATE;
        PROTECTED;
        PUBLIC;
        READONLY;
        RECORD;
        REF;
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
        case .kwm_explicit;  return .EXPLICIT;
        case .kwm_extern;    return .EXTERN;
        case .kwm_file;      return .FILE;
        case .kwm_global;    return .GLOBAL;
        case .kwm_implicit;  return .IMPLICIT;
        case .kwm_internal;  return .INTERNAL;
        case .kwm_in;        return .IN;
        case .kwm_new;       return .NEW;
        case .kwm_out;       return .OUT;
        case .kwm_override;  return .OVERRIDE;
        case .kwm_params;    return .PARAMS;
        case .kwm_private;   return .PRIVATE;
        case .kwm_protected; return .PROTECTED;
        case .kwm_public;    return .PUBLIC;
        case .kwm_readonly;  return .READONLY;
        case .kwm_record;    return .RECORD;
        case .kwm_ref;       return .REF;
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


get_tokenizer :: (using buffer: Buffer) -> *CSTokenizer {
    tokenizer := New(CSTokenizer,, temp);

    tokenizer.buf   = cast(string) bytes;
    tokenizer.max_t = bytes.data + bytes.count;
    tokenizer.t     = bytes.data;
    add_recent_token(tokenizer, .{0, 0, "", .eof, .DEFAULT, 0});

    return tokenizer;
}


get_next_token :: (using tokenizer: *CSTokenizer) -> CSToken {
    if tokenizer.return_eol
        t = eat_white_space_no_newline(t, max_t);
    else
        t = eat_white_space(t, max_t);

    token: CSToken;
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
        token.type = .eol; t = unicode_next_character(t);
    } else if char == {
        // https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/operators/
        case #char "=";  parse_equal                 (tokenizer, *token);
        case #char "-";  parse_minus                 (tokenizer, *token);
        case #char "+";  parse_plus                  (tokenizer, *token);
        case #char "*";  parse_asterisk              (tokenizer, *token);
        case #char "<";  parse_less_than             (tokenizer, *token);
        case #char ">";  parse_greater_than          (tokenizer, *token);
        case #char "!";  parse_bang                  (tokenizer, *token);
        case #char "#";  parse_directive             (tokenizer, *token);
        case #char "\""; parse_string_literal        (tokenizer, *token);
        case #char "'";  parse_char_literal          (tokenizer, *token);
        case #char "/";  parse_slash_or_comment      (tokenizer, *token);
        case #char "&";  parse_ampersand             (tokenizer, *token);
        case #char "|";  parse_pipe                  (tokenizer, *token);
        case #char "%";  parse_percent               (tokenizer, *token);
        case #char "@";  parse_at                    (tokenizer, *token);
        case #char "^";  parse_caret                 (tokenizer, *token);
        case #char "$";  parse_dollar                (tokenizer, *token);
        case #char ":";  token.type = .operation;   token.operation = .colon;       t = unicode_next_character(t);
        case #char "?";  token.type = .operation;   token.operation = .question;    t = unicode_next_character(t);
        case #char "~";  token.type = .operation;   token.operation = .tilde;       t = unicode_next_character(t);

        case #char ";";  token.type = .punctuation; token.punctuation = .semicolon; t = unicode_next_character(t);
        case #char "\\"; token.type = .punctuation; token.punctuation = .backslash; t = unicode_next_character(t);
        case #char ",";  token.type = .punctuation; token.punctuation = .comma;     t = unicode_next_character(t);
        case #char ".";  token.type = .punctuation; token.punctuation = .period;    t = unicode_next_character(t);
        case #char "{";  token.type = .punctuation; token.punctuation = .l_brace;   t = unicode_next_character(t);
        case #char "}";  token.type = .punctuation; token.punctuation = .r_brace;   t = unicode_next_character(t);
        case #char "(";  token.type = .punctuation; token.punctuation = .l_paren;   t = unicode_next_character(t);
        case #char ")";  token.type = .punctuation; token.punctuation = .r_paren;   t = unicode_next_character(t);
        case #char "[";  token.type = .punctuation; token.punctuation = .l_bracket; t = unicode_next_character(t);
        case #char "]";  token.type = .punctuation; token.punctuation = .r_bracket; t = unicode_next_character(t);

        case;            token.type = .invalid; t = unicode_next_character(t);
    }

    if t >= max_t then t = max_t;
    token.len = cast(s32) (t - start_t);
    token.as_string.count = token.len;

    return token;
}

parse_identifier :: (using tokenizer: *CSTokenizer, token: *CSToken, check_for_keyword: bool) {
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
parse_number :: (using tokenizer: *CSTokenizer, token: *CSToken) {
    token.type = .number;

    is_floating_point_suffix :: (c: u8) -> bool {
        return c == #char "f" || c == #char "F" || c == #char "d" || c == #char "D" || c == #char "m" || c == #char "M";
    }

    // Consecutive underscores are allowed in numbers but they can't end in one.
    is_valid_underscore :: (t: *u8, max_t: *u8, allowed: (u8) -> bool) -> bool {
        next := unicode_next_character(t);
        return <<t == #char "_" && (next < max_t && (allowed(<<next) || <<next == #char "_"));
    }

    t = unicode_next_character(t);
    if t >= max_t return;

    if <<t == #char "x" || <<t == #char "X" {
        // Hex
        t = unicode_next_character(t);
        while t < max_t && (is_hex(<<t) || is_valid_underscore(t, max_t, is_hex)) t = unicode_next_character(t);
        return;
    } else if <<t == #char "b" || <<t == #char "B" {
        // Binary
        t = unicode_next_character(t);
        is_binary :: inline (c: u8) -> bool { return c == #char "1" || c == #char "0"; }
        while t < max_t && (is_binary(<<t) || is_valid_underscore(t, max_t, is_binary)) t = unicode_next_character(t);
        return;
    }

    // Eat initial digits/underscores
    while t < max_t && (is_digit(<<t) || is_valid_underscore(t, max_t, is_digit)) {
        t = unicode_next_character(t);
    }
    if t >= max_t return;

    if <<t == #char "." {
        // Float, double or decimal
        // First char after a decimal point must be a digit(cannot be an underscore).
        t = unicode_next_character(t);
        if t >= max_t || !is_digit(<<t) { token.type = .invalid; return; }

        // Eat digits/underscores after the decimal point
        t = unicode_next_character(t);
        while t < max_t && (is_digit(<<t) || is_valid_underscore(t, max_t, is_digit)) {
            t = unicode_next_character(t);
        }

        if t >= max_t return;

        // Exponent
        if <<t == #char "e" || <<t == #char "E" {
            t = unicode_next_character(t);
            if t >= max_t return;

            if <<t == #char "+" || <<t == #char "-" {
              t = unicode_next_character(t);
              if t >= max_t return;
            }

            while t < max_t && (is_digit(<<t) || is_valid_underscore(t, max_t, is_digit)) {
                t = unicode_next_character(t);
            }
            if t >= max_t return;
        }

        // Floating point suffixes
        if is_floating_point_suffix(<<t) t = unicode_next_character(t);
    } else {
        if is_floating_point_suffix(<<t) {
            // Floating point suffixes (can occur without a decimal point)
            t = unicode_next_character(t);
        } else {
            // Integer suffixes
            if <<t == #char "l" || <<t == #char "L" { // l, L
                t = unicode_next_character(t);
                if t >= max_t return;

                if <<t == #char "u" || <<t == #char "U" {  // lu, lU, Lu, LU
                    t = unicode_next_character(t);
                }
            } else if <<t == #char "u" || <<t == #char "U" { // u, U
                t = unicode_next_character(t);
                if t >= max_t return;

                if <<t == #char "l" || <<t == #char "L" {  // ul, uL, Ul, UL
                    t = unicode_next_character(t);
                }
            }
        }
    }
}

parse_equal :: (using tokenizer: *CSTokenizer, token: *CSToken) {
    token.type = .operation;
    token.operation = .equal;

    t = unicode_next_character(t);
    if t >= max_t return;

    if <<t == #char "=" {
        token.operation = .equal_equal;
        t = unicode_next_character(t);
    }
    else if <<t == #char ">" {
        token.operation = .equal_greater_than;
        t = unicode_next_character(t);
    }
}


parse_minus :: (using tokenizer: *CSTokenizer, token: *CSToken) {
    token.type = .operation;
    token.operation = .minus;

    t = unicode_next_character(t);
    if t >= max_t return;

    if <<t == {
        case #char "=";
            token.operation = .minus_equal;
            t = unicode_next_character(t);
        case #char ">";
            // https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/unsafe-code?#pointer-types
            token.operation = .arrow;
            t = unicode_next_character(t);
        case #char "-";
            token.operation = .minus_minus;
            t = unicode_next_character(t);
    }
}

parse_plus :: (using tokenizer: *CSTokenizer, token: *CSToken) {
    token.type = .operation;
    token.operation = .plus;

    t = unicode_next_character(t);
    if t >= max_t return;

    if <<t == {
        case #char "=";
            token.operation = .plus_equal;
            t = unicode_next_character(t);
        case #char "+";
            token.operation = .plus_plus;
            t = unicode_next_character(t);
    }
}

parse_asterisk :: (using tokenizer: *CSTokenizer, token: *CSToken) {
    token.type = .operation;
    token.operation = .asterisk;

    t = unicode_next_character(t);
    if t >= max_t return;

    if <<t == #char "=" {
        token.operation = .asterisk_equal;
        t = unicode_next_character(t);
    }
}

parse_less_than :: (using tokenizer: *CSTokenizer, token: *CSToken) {
    token.type = .operation;
    token.operation = .less_than;

    t = unicode_next_character(t);
    if t >= max_t return;

    if <<t == {
        case #char "=";
            token.operation = .less_than_equal;
            t = unicode_next_character(t);
        case #char "<";
            if <<unicode_next_character(t) == #char "=" {
                token.operation = .double_less_than_equal;
                t = unicode_next_character(t);
                t = unicode_next_character(t);
            }
    }
}

parse_greater_than :: (using tokenizer: *CSTokenizer, token: *CSToken) {
    token.type = .operation;
    token.operation = .greater_than;

    t = unicode_next_character(t);
    if t >= max_t return;

    if <<t == {
        case #char "=";
            token.operation = .greater_than_equal;
            t = unicode_next_character(t);
        case #char ">";
            if <<unicode_next_character(t) == #char "=" {
                token.operation = .double_greater_than_equal;
                t = unicode_next_character(t);
                t = unicode_next_character(t);
            }
    }
}

parse_bang :: (using tokenizer: *CSTokenizer, token: *CSToken) {
    token.type = .operation;
    token.operation = .bang;

    t = unicode_next_character(t);
    if t >= max_t return;

    if <<t == {
        case #char "=";
            token.operation = .bang_equal;
            t = unicode_next_character(t);
    }
}

parse_directive :: (using tokenizer: *CSTokenizer, token: *CSToken) {
    token.type = .identifier;

    t = unicode_next_character(t);
    t = eat_white_space(t, max_t);  // There may be spaces between the # and the name
    if !is_alpha(<<t) return;

    directive := read_identifier_string(tokenizer);

    while t < max_t && is_alnum(<<t) t = unicode_next_character(t);
    if t >= max_t return;

    // Check if it's one of the existing directives
    if directive.count > MAX_DIRECTIVE_LENGTH return;
    token_directive, ok := table_find(*PREPROCESSOR_DIRECTIVES_MAP, directive);
    if ok {
        token.type = .directive;
        token.directive = token_directive;
    }
}

parse_string_literal :: (using tokenizer: *CSTokenizer, token: *CSToken) {
    token.type = .string_literal;

    escape_seen := false;

    t = unicode_next_character(t);
    while t < max_t && <<t != #char "\n" {
        if <<t == #char "\"" && !escape_seen break;
        escape_seen = !escape_seen && <<t == #char "\\";
        t = unicode_next_character(t);
    }
    if t >= max_t return;

    t = unicode_next_character(t);
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
parse_char_literal :: (using tokenizer: *CSTokenizer, token: *CSToken) {
    token.type = .invalid;

    escape_seen := false;

    t = unicode_next_character(t);
    if t >= max_t || <<t == #char "\n" return;

    if <<t == #char "\\" {
        escape_seen = true;
        t = unicode_next_character(t);
        if t >= max_t || <<t == #char "\n" return;
    } else if <<t == #char "'" {
        // Unescaped single quote without a character
        t = unicode_next_character(t); // Invalid '
        return;
    }

    if escape_seen {
        if !is_valid_character_escape_character(<<t) {
            return;
        } else if <<t == #char "u" {
            // u must be followed by 4 hex characters
            t = unicode_next_character(t); count := 0;
            while t < max_t && count < 4 {
                if !is_hex(<<t) { t = unicode_next_character(t); return; }
                count += 1;
                t = unicode_next_character(t);
            }
            if t >= max_t || <<t == #char "\n" return;
        } else if <<t ==#char "x" {
            t = unicode_next_character(t);
            // x must be followed by at least one hex character
            if t >= max_t || !is_hex(<<t) return;
            while t < max_t && is_hex(<<t) t = unicode_next_character(t);
        } else {
            // A single valid character after the escape like '\n'
            t = unicode_next_character(t);
        }
    } else {
        t = unicode_next_character(t); // Unescaped single character
    }

    if t >= max_t || <<t == #char "\n" || <<t != #char "'" return;

    token.type = .char_literal;
    t = unicode_next_character(t); // Ending '
}

parse_slash_or_comment :: (using tokenizer: *CSTokenizer, token: *CSToken) {
    token.type = .operation;
    token.operation = .slash;

    t = unicode_next_character(t);
    if t >= max_t return;

    if <<t == {
        case #char "=";
            token.operation = .slash_equal;
            t = unicode_next_character(t);
        case #char "/";
            token.type = .comment;
            t = unicode_next_character(t);
            while t < max_t && <<t != #char "\n" t = unicode_next_character(t);
        case #char "*";
            token.type = .multiline_comment;
            t = unicode_next_character(t);
            while t + 1 < max_t {
                if <<t == #char "*" && <<(t + 1) == #char "/" {
                  t += 2;
                  break;
                }
                t = unicode_next_character(t);
            }
    }
}

parse_ampersand :: (using tokenizer: *CSTokenizer, token: *CSToken) {
    token.type = .operation;
    token.operation = .ampersand;

    t = unicode_next_character(t);
    if t >= max_t return;

    if <<t == {
        case #char "=";
            token.operation = .ampersand_equal;
            t = unicode_next_character(t);
        case #char "&";
            token.operation = .double_ampersand;
            t = unicode_next_character(t);
    }
}

parse_pipe :: (using tokenizer: *CSTokenizer, token: *CSToken) {
    token.type = .operation;
    token.operation = .pipe;

    t = unicode_next_character(t);
    if t >= max_t return;

    if <<t == {
        case #char "=";
            token.operation = .pipe_equal;
            t = unicode_next_character(t);
        case #char "|";
            token.operation = .double_pipe;
            t = unicode_next_character(t);
    }
}

parse_percent :: (using tokenizer: *CSTokenizer, token: *CSToken) {
    token.type = .operation;
    token.operation = .percent;

    t = unicode_next_character(t);
    if t >= max_t return;

    if <<t == {
        case #char "=";
            token.operation = .percent_equal;
            t = unicode_next_character(t);
    }
}

parse_verbatim_string_literal :: (using tokenizer: *CSTokenizer, token: *CSToken) {
    token.type = .string_literal;

    escape_seen := false;

    t = unicode_next_character(t);
    while t < max_t && <<t != #char "\n" {
        if escape_seen && <<t != #char "\"" { t -= 1; break; }
        escape_seen = !escape_seen && <<t == #char "\"";
        t = unicode_next_character(t);
    }
    if t >= max_t return;

    t = unicode_next_character(t);
}

// https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/tokens/verbatim
// https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/language-specification/attributes
parse_at :: (using tokenizer: *CSTokenizer, token: *CSToken) {
    token.type = .invalid;

    t = unicode_next_character(t);
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
parse_dollar :: (using tokenizer: *CSTokenizer, token: *CSToken, verbatim := false) {
    token.type = .invalid;

    t = unicode_next_character(t);
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

parse_caret :: (using tokenizer: *CSTokenizer, token: *CSToken) {
    token.type = .operation;
    token.operation = .caret;

    t = unicode_next_character(t);
    if t >= max_t return;

    if <<t == {
        case #char "=";
            token.operation = .caret_equal;
            t = unicode_next_character(t);
    }
}

read_identifier_string :: (using tokenizer: *CSTokenizer) -> string {
    identifier: string;
    identifier.data = t;

    while t < max_t && is_alnum(<<t) {
        t = unicode_next_character(t);
    }
    if t >= max_t then t = max_t;
    identifier.count = t - identifier.data;

    return identifier;
}

eat_white_space_no_newline :: inline (start: *u8, max_t: *u8) -> *u8 {
    t := start;
    while t < max_t && (t.* != #char "\n" && is_white_space(t.*)) {
        t = unicode_next_character(t);
    }
    return t;
}

eat_white_space :: inline (start: *u8, max_t: *u8) -> *u8 {
    t := start;
    while t < max_t && is_white_space(t.*) {
        t = unicode_next_character(t);
    }
    return t;
}

get_recent_token :: (tokenizer: *CSTokenizer, offset: int) -> *CSToken {
    assert(offset <= 0);
    i := tokenizer.recent_token_head + offset;
    if i < 0  i += tokenizer.recent_tokens.count;
    return *tokenizer.recent_tokens[i];
}

add_recent_token ::(tokenizer: *CSTokenizer, token: CSToken) {
    tokenizer.recent_token_head = (tokenizer.recent_token_head + 1) % tokenizer.recent_tokens.count;
    tokenizer.recent_tokens[tokenizer.recent_token_head] = token;
}


CSResult :: struct {
    state : enum {
        ATE_TERMINATOR;
        LEFT_TERMINATOR;
        ERROR;
    }

    error: string;
}


CSTokenizer :: struct {
    buf: string;
    max_t:   *u8;
    start_t: *u8;  // Cursor when starting parsing new token
    t:       *u8;  // Cursor

    return_eol := false;

    last_identifier_token: CSToken;
    recent_tokens: [64] CSToken;
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

CSToken :: struct {
    start, len: s32;
    as_string: string;
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
        function;
        attribute;
    }

    color: Code_Color;
    attached_up_to_index: int;
}


is_keyword :: (type: CSToken.Type) -> bool {
    return type == .keyword || type == .jump_keyword || type == .value_keyword || type == .modifier_keyword || type == .type_keyword;
}

is_keyword :: (token: *CSToken, keyword: Keyword) -> bool {
    return is_keyword(token.type) && token.keyword == keyword;
}

is_modifier :: (token: *CSToken, keyword: Keyword) -> bool {
    return token.type == .modifier_keyword && token.keyword == keyword;
}

is_punctuation :: (token: *CSToken, punctuation: Punctuation) -> bool {
    return token.type == .punctuation && token.punctuation == punctuation;
}

is_operation :: (token: *CSToken, operation: Operation) -> bool {
    return token.type == .operation && token.operation == operation;
}

is_directive :: (token: *CSToken, directive: Directive) -> bool {
    return token.type == .directive && token.directive == directive;
}


expect_token :: (offset := 0) -> *CSToken #expand #no_debug {
    proc_name :: #procedure_name(#this);

    token := peek_token(offset);
    if !token  `return .{.ERROR, #run sprint("EOF in %", proc_name)};
    return token;
}

eat_identifier :: () -> *CSToken #expand #no_debug {
    proc_name :: #procedure_name(#this);

    token := peek_token();
    if !token  `return .{.ERROR, #run sprint("EOF in %", proc_name)};

    if token.type != .identifier
        `return .{.ERROR, #run sprint("Expected identifier in %", proc_name)};

    eat_token();
    return token;
}

eat_until_punctuation :: (terminator1: Punctuation, terminator2: Punctuation) -> *CSToken #expand {
    while true {
        token := peek_token();
        if !token || token.type == .punctuation && (token.punctuation == terminator1 || token.punctuation == terminator2)
            return token;
        eat_token();
    }
}

eat_array_punctuation :: () -> is_array: bool #expand #no_debug {
    proc_name :: #procedure_name(#this);

    token := peek_token();
    if !token  `return .{.ERROR, #run sprint("EOF in ", proc_name)};

    if !is_punctuation(token, .l_bracket)
        return false;

    while true {
        eat_token();
        token = peek_token();
        if !token  `return .{.ERROR, #run sprint("EOF in ", proc_name)};

        while is_punctuation(token, .comma) {
            eat_token();
            token = peek_token();
            if !token  `return .{.ERROR, #run sprint("EOF in ", proc_name)};
        }

        `eat_punctuation(.r_bracket);

        token = peek_token();
        if !token  `return .{.ERROR, #run sprint("EOF in ", proc_name)};

        if !is_punctuation(token, .l_bracket)
            return true;
    }

    return true;
}


eat_identifier_dot_chain :: (accept_type := false) -> *CSToken {
    using context.csharp;

    first_token := peek_token();

    while true {
        token := peek_token();
        if !(token && (token.type == .identifier || (accept_type && token.type == .type_keyword)))
            return null;

        eat_token();
        token = peek_token();
        if !is_punctuation(token, .period) {
            first_token.attached_up_to_index = token_index;
            return first_token;
        }

        eat_token();
    }

    return null;  // unreachable
}


eat_array_declaration_tail :: () -> ok: bool {
    // This is for empty [] in declarations, not [foo] or [1] or w/e
    while true {
        token := peek_token();
        if !token || token.type != .punctuation
            return false;

        if token.punctuation == {
            case .comma;
                eat_token();
            case .r_bracket;
                eat_token();
                return true;
            case;
                return false;
        }
    }

    return false;  // unreachable
}


try_eat_generic :: () -> bool {
    using context.csharp;

    while true {
        token := peek_token();
        if !token || (token.type != .identifier && token.type != .type_keyword)
            return false;
        eat_token();

        token = peek_token();
        if token && is_punctuation(token, .l_bracket) {
            eat_token();
            ok := eat_array_declaration_tail();
            if !ok  return false;
            token = peek_token();
        }

        if !token  return false;

        if is_operation(token, .less_than) {
            eat_token();
            success := try_eat_generic();
            if !success  return false;

            eat_token();
            token = peek_token();
            if !token  return true;
        }

        if is_operation(token, .greater_than)
            return true;

        if is_punctuation(token, .comma)
            eat_token();
        else
            return false;
    }

    return false; // unreachable
}


index_from_pointer :: (token: *CSToken) -> int {
    using context.csharp;
    return token - tokens.data;
}


eat_generic :: (accept_type := false, paint_as_type := false) -> *CSToken, is_generic: bool {
    using context.csharp;

    identifier := eat_identifier_dot_chain(accept_type);
    if !identifier  return null, false;

    if paint_as_type  paint_identifier(identifier, .type_keyword);
    maybe_eat_nullable(identifier);

    token := peek_token();
    if !token || !is_operation(token, .less_than)
        return identifier, false;

    non_generic_token_index := token_index;
    eat_token();
    success := try_eat_generic();
    if success {
        paint_identifiers(non_generic_token_index, token_index, .type_keyword);
        eat_token();
    }
    else {
        token_index = non_generic_token_index;
    }
    return identifier, success;
}


eat_punctuation :: (punctuation: Punctuation) -> *CSToken #expand #no_debug {
    proc_name :: #procedure_name(#this);

    token := peek_token();
    if !token  `return .{.ERROR, #run sprint("EOF in %", proc_name)};

    if !is_punctuation(token, punctuation)
        `return .{.ERROR, #run sprint("Expected % in %", punctuation, proc_name)};

    eat_token();
    return token;
}


eat_operation :: (operation: Operation) -> *CSToken #expand #no_debug {
    proc_name :: #procedure_name(#this);

    token := peek_token();
    if !token  `return .{.ERROR, #run sprint("EOF in %", proc_name)};

    if !is_operation(token, operation)
        `return .{.ERROR, #run sprint("Expected % in %", operation, proc_name)};

    eat_token();
    return token;
}

eat_keyword :: (keyword: Keyword) -> *CSToken #expand #no_debug {
    proc_name :: #procedure_name(#this);

    token := peek_token();
    if !token  `return .{.ERROR, #run sprint("EOF in %", proc_name)};

    if !is_keyword(token, keyword)
        `return .{.ERROR, #run sprint("Expected % in %", keyword, proc_name)};

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
    kw_base;
    kw_case;
    kw_checked;
    kw_class;
    kw_default;
    kw_do;
    kw_else;
    kw_enum;
    kw_fixed;
    kw_for;
    kw_foreach;
    kw_if;
    kw_interface;
    kw_lock;
    kw_namespace;
    kw_operator;
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
    kwm_explicit;
    kwm_extern;
    kwm_file;
    kwm_global;
    kwm_implicit;
    kwm_in;
    kwm_internal;
    kwm_out;
    kwm_new;
    kwm_override;
    kwm_params;
    kwm_private;
    kwm_protected;
    kwm_public;
    kwm_readonly;
    kwm_record;
    kwm_ref;
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
    kw_when;
    kw_where;
    kw_with;

    kwt_nint;
    kwt_nuint;
    kwt_var;

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
    equal_greater_than;
    bang_equal;
    percent;
    percent_equal;
    less_than;
    less_than_equal;
    double_less_than_equal;
    greater_than;
    greater_than_equal;
    double_greater_than_equal;
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
    as;
    is;
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
        case .double_less_than_equal; #through;
        case .double_greater_than_equal; #through;
        case .caret_equal;
            return true;

        case;
            return false;
    }
}

is_modify_in_place_operation :: (operation: Operation) -> bool {
    return operation == .plus_plus || operation == .minus_minus;
}

NO_PUNCTUATION :: () -> Punctuation #expand {
    return #run cast(Punctuation) 65535;
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
    type: CSToken.Type;
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
        } else if starts_with(name, "kwv") && name != "kwv_value" {
            table_add(*table, slice(name, 4), .{.value_keyword, it});
        } else if starts_with(name, "kwj") {
            table_add(*table, slice(name, 4), .{.jump_keyword, it});
        } else if starts_with(name, "kwf") {
            table_add(*table, slice(name, 4), .{.function, it});
        } else {
            table_add(*table, slice(name, 3), .{.keyword, it});
        }
    }

    // These keywords act like operators, but we kludge them into the keyword table to make tokenisation simple.
    table_add(*table, "as", .{.operation, cast(Keyword) Operation.as});
    table_add(*table, "is", .{.operation, cast(Keyword) Operation.is});

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

#run assert(type_info(CSToken.Type).values.count == COLOR_MAP.count);
