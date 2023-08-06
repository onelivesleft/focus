language_from_extension :: (identifier: string) -> type_of(Buffer.lang) {

    matches :: (postfix: string) -> bool #expand {
        return ends_with(identifier, postfix, ignore_case);
    }

    if matches("jai")
        return .Jai;
    else if matches("cs") || matches("csharp") || matches("c#")
        return .CSharp;
    else if matches("cpp") || matches("c++") || matches("c") || matches("h") || matches("h++") || matches("hpp")
        return .C;
    else if matches("vert") || matches("frag") || matches("geom") || matches("tess") || matches("glsl")
        return .Glsl;
    else if matches("md") || matches("markdown")
        return .Markdown;

    return .Plain_Text;
}

maybe_highlight_inner_language :: (using buffer: *Buffer, language: type_of(Buffer.lang), start_index: s32, count: s32, use_jai_by_default := false) -> bool {
    highlight_proc : #type (*Buffer, s32, s32);

    // @TODO generate this code at compile time
    if #complete language == {
        case .Jai;           highlight_proc = highlight_jai_syntax;
        case .CSharp;        highlight_proc = highlight_csharp_syntax;
        case .C;             highlight_proc = highlight_c_syntax;
        case .Glsl;          highlight_proc = highlight_glsl_syntax;
        case .Markdown;      highlight_proc = highlight_md_syntax;
        case .Worklog;       highlight_proc = highlight_worklog;
        case .Focus_Config;  highlight_proc = highlight_focus_config_syntax;

        case .Plain_Text;
        if use_jai_by_default
            highlight_proc = highlight_jai_syntax;
        else
            return false;
    }

    highlight_proc(buffer, start_index, count);
    return true;
}

is_lang_which_likes_to_line_wrap :: (lang: type_of(Buffer.lang)) -> bool {
    return lang == .Plain_Text
        || lang == .Focus_Config
        || lang == .Markdown
        || lang == .Worklog;
}

is_lang_which_likes_to_indent :: (lang: type_of(Buffer.lang)) -> bool {
    return lang == .Jai
        || lang == .C
        || lang == .CSharp
        || lang == .Glsl;
}


#scope_file


is_whitespace :: inline (char: u8) -> bool {
    return char == #char " " || char == #char "\t" || char == #char "\r" || char == #char "\n";
}
