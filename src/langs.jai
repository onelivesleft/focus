Language :: enum u8 {
    Plain_Text :: 0;
    C;
    CSharp;
    Ficus;
    Focus_Config;
    Glsl;
    Golang;
    Jai;
    Odin;
    Markdown;
    Python;
    RenPy;
    Worklog;
}

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

    else if matches("focus") || matches("focus_config")
        return .Focus_Config;

    else if matches("fig")
        return .Ficus;

    else if matches("py") || matches("pyw")
        return .Python;

    else if matches("ren")
        return .RenPy;

    return .Plain_Text;
}

maybe_highlight_inner_language :: (using buffer: *Buffer, language: type_of(Buffer.lang), start_index: s32, count: s32, use_jai_by_default := false) -> bool {
    highlight_proc : #type (*Buffer, s32, s32);

    // @TODO generate this code at compile time
    if #complete language == {
        case .Jai;           highlight_proc = highlight_jai_syntax;
        case .CSharp;        highlight_proc = highlight_csharp_syntax;
        case .C;             highlight_proc = highlight_c_syntax;
        case .Golang;        highlight_proc = highlight_golang_syntax;
        case .Glsl;          highlight_proc = highlight_glsl_syntax;
        case .Markdown;      highlight_proc = highlight_md_syntax;
        case .Worklog;       highlight_proc = highlight_worklog;
        case .Focus_Config;  highlight_proc = highlight_focus_config_syntax;
        case .Ficus;         highlight_proc = highlight_ficus_syntax;
        case .Python;        highlight_proc = highlight_python_syntax;
        case .RenPy;         highlight_proc = highlight_renpy_syntax;

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
        || lang == .Golang
        || lang == .Glsl;
}

icon_for_lang :: (lang: type_of(Buffer.lang)) -> File_Icon {
    if #complete lang == {
        case .Jai;           return .jai;
        case .CSharp;        return .cs;
        case .C;             return .cpp;
        case .Golang;        return .unknown;
        case .Glsl;          return .unknown;
        case .Markdown;      return .unknown;
        case .Worklog;       return .worklog;
        case .Focus_Config;  return .gear;
        case .Ficus;         return .fig;
        case .Plain_Text;    return .text;
        case .Python;        return .unknown;
        case .RenPy;         return .unknown;
    }
}
