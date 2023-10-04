Color :: struct {
    #as vec4 : Vector4 = ---;

    #place vec4;
    using components : struct { r, g, b, a : float = 1; };

    #place vec4;
    floats : [4] float = ---;
}

Color_Values :: struct {
    NONE :: Color.{ r = -1, g = -1, b = -1, a = -1 };  // an invalid color to denote no color

    BACKGROUND                := Color.{ r = 0.086, g = 0.133, b = 0.165 };
    BACKGROUND_DARK           := Color.{ r = 0.065, g = 0.101, b = 0.125 };
    BACKGROUND_HIGHLIGHT      := Color.{ r = 0.097, g = 0.15, b = 0.185 };
    BACKGROUND_LIGHT          := Color.{ r = 0.102, g = 0.158, b = 0.195 };
    BACKGROUND_BRIGHT         := Color.{ r = 0.131, g = 0.202, b = 0.25 };
    BACKGROUND_REGION         := Color.{ r = 0.131, g = 0.202, b = 0.25, a = 0.02 };
    BACKGROUND_REGION_PRIVATE := Color.{ r = 0.165, g = 0.086, b = 0.133 };
    BACKGROUND_REGION_PUBLIC  := Color.{ r = 0.086, g = 0.165, b = 0.133 };
    BACKGROUND_CURSOR_ROW     := Color.{ r = 1.0, g = 1.0, b = 1.0, a = 0.1 };

    SELECTION_ACTIVE        := Color.{ r = 0.11, g = 0.267, b = 0.29 };
    SELECTION_INACTIVE      := Color.{ r = 0.11, g = 0.267, b = 0.29, a = 0.5 };
    SELECTION_HIGHLIGHT     := Color.{ r = 0.99, g = 0.93, b = 0.99, a = 0.15 };
    SEARCH_RESULT_ACTIVE    := Color.{ r = 0.559, g = 0.469, b = 0.184 };
    SEARCH_RESULT_INACTIVE  := Color.{ r = 0.99, g = 0.93, b = 0.99, a = 0.15 };
    SCROLLBAR               := Color.{ r = 0.20, g = 0.80, b = 0.80, a = 0.1 };
    SCROLLBAR_HOVER         := Color.{ r = 0.20, g = 0.80, b = 0.80, a = 0.3 };
    SCROLLBAR_BACKGROUND    := Color.{ r = 0.065, g = 0.101, b = 0.125, a = 0.3 };
    CURSOR                  := Color.{ r = 0.15, g = 0.7, b = 0.7 };
    CURSOR_INACTIVE         := Color.{ r = 0.10, g = 0.4, b = 0.4 };
    PASTE_ANIMATION         := Color.{ r = 0.11, g = 0.267, b = 0.29 };
    SPLITTER                := Color.{ r = 0.131, g = 0.202, b = 0.25 };
    SPLITTER_HOVER          := Color.{ r = 0.110, g = 0.267, b = 0.29 };
    LETTER_HIGHLIGHT        := Color.{ r = 0.35, g = 0.6, b = 0.6 };
    LIST_CURSOR_LITE        := Color.{ r = 0.20, g = 0.80, b = 0.80, a = 0.1 };  // @TODO: do without alpha?
    LIST_CURSOR             := Color.{ r = 0.20, g = 0.80, b = 0.80, a = 0.3 };
    SHADOW_DARK             := Color.{ r = 0.057, g = 0.089, b = 0.11, a = 0.5 };
    SHADOW_TRANSPARENT      := Color.{ r = 0.057, g = 0.089, b = 0.11, a = 0 };  // for interpolation
    TEXT_INPUT_LABEL        := Color.{ r = 0.233, g = 0.269, b = 0.316, a = 1.0 };
    MOTIF                   := Color.{ r = 0.359, g = 0.269, b = 0.124 };
    COLLAPSED_AREA_MARKER   := Color.{ r = 0.75, g = 0.79, b = 0.86, a = 0.8 };
    GUTTER                  := Color.{ r = 0.0, g = 0.0, b = 0.0, a = 0.1 };

    CONSOLE_BACKGROUND      := Color.{ r = 0.065, g = 0.101, b = 0.125 };
    CONSOLE_TEXT            := Color.{ r = 0.75, g = 0.79, b = 0.86, a = 1.0 };
    CONSOLE_ERROR           := Color.{ r = 1.00, g = 0.00, b = 0.00, a = 1.0 };
    CONSOLE_HEADER_BACKGROUND := Color.{ r = 0.131, g = 0.202, b = 0.25 };
    CONSOLE_HEADER_SUCCESS  := Color.{ r = 0.10, g = 0.50, b = 0.10, a = 1.0 };
    CONSOLE_HEADER_ERROR    := Color.{ r = 0.50, g = 0.00, b = 0.00, a = 1.0 };
    CONSOLE_HEADER_TEXT     := Color.{ r = 0.75, g = 0.79, b = 0.86, a = 1.0 };

    ZEN_FOREGROUND          := Color.{r = 0.6,      g = 0.6,      b = 0.666667, a = 0.686275};
    ZEN_BACKGROUND          := Color.{r = 0.058824, g = 0.027451, b = 0,        a = 0.498039};
    ZEN_MARGINS             := Color.{r = 0.011765, g = 0.011765, b = 0.011765, a = 1};
    ZEN_COMMENT             := Color.{r = 0.266667, g = 0.266667, b = 0.266667, a = 1};
    ZEN_CURSOR              := Color.{r = 1,        g = 1,        b = 1,        a = 0.666667};

    UI_DEFAULT              := Color.{ r = 0.75, g = 0.79, b = 0.86, a = 1.0 };
    UI_DIM                  := Color.{ r = 0.533, g = 0.569, b = 0.616, a = 1.0 };
    UI_NEUTRAL              := Color.{ r = 0.3, g = 0.3, b = 0.3, a = 1.0 };
    UI_MESSAGE              := Color.{ r = 0.131, g = 0.202, b = 0.25, a = 1.0 };
    UI_WARNING              := Color.{ r = 0.85, g = 0.68, b = 0.33, a = 1.0 };
    UI_WARNING_DIM          := Color.{ r = 0.59, g = 0.37, b = 0.19, a = 1.0 };
    UI_ERROR                := Color.{ r = 0.46, g = 0.13, b = 0.13, a = 1.0 };
    UI_ERROR_BRIGHT         := Color.{ r = 1.00, g = 0.00, b = 0.00, a = 1.0 };
    UI_SUCCESS              := Color.{ r = 0.10, g = 0.50, b = 0.10, a = 1.0 };

    UI_BACKGROUND_0         := Color.{ r = 0.250, g = 0.131, b = 0.202 };
    UI_BACKGROUND_1         := Color.{ r = 0.202, g = 0.250, b = 0.131 };
    UI_BACKGROUND_2         := Color.{ r = 0.250, g = 0.202, b = 0.131 };
    UI_BACKGROUND_3         := Color.{ r = 0.131, g = 0.250, b = 0.202 };
    UI_BACKGROUND_4         := Color.{ r = 0.131, g = 0.202, b = 0.250 };
    UI_BACKGROUND_5         := Color.{ r = 0.202, g = 0.131, b = 0.250 };

    CODE_DEFAULT            := Color.{ r = 0.75, g = 0.79, b = 0.86, a = 1.0 };
    CODE_COMMENT            := Color.{ r = 0.533, g = 0.569, b = 0.616, a = 1.0 };
    CODE_TYPE               := Color.{ r = 0.51, g = 0.67, b = 0.64, a = 1.0 };
    CODE_FUNCTION           := Color.{ r = 0.816, g = 0.776, b = 0.663, a = 1.0 };
    CODE_PUNCTUATION        := Color.{ r = 0.75, g = 0.79, b = 0.86, a = 1.0 };
    CODE_OPERATION          := Color.{ r = 0.88, g = 0.68, b = 0.51, a = 1.0 };
    CODE_STRING             := Color.{ r = 0.835, g = 0.74, b = 0.494, a = 1.0 };
    CODE_VALUE              := Color.{ r = 0.84, g = 0.60, b = 0.71, a = 1.0 };
    CODE_HIGHLIGHT          := Color.{ r = 0.85, g = 0.61, b = 0.46, a = 1.0 };
    CODE_ERROR              := Color.{ r = 1.00, g = 0.00, b = 0.00, a = 1.0 };
    CODE_JUMP               := Color.{ r = 0.902, g = 0.493, b = 0.457, a = 1.0 };
    CODE_DIRECTIVE          := Color.{ r = 0.493, g = 0.902, b = 0.457, a = 1.0 };
    CODE_KEYWORD            := Color.{ r = 0.902, g = 0.493, b = 0.457, a = 1.0 };
    CODE_FORMAT_ITEM        := Color.{ r = 0.493, g = 0.902, b = 0.902, a = 1.0 };
};

operator + :: (a: Color, b: Color) -> Color {
    return Color.{r = a.r + b.r, g = a.g + b.g, b = a.b + b.b, a = a.a + b.a};
}

Colors: Color_Values;  // a hack to avoid replacing a lot of code
Loaded_Colors: Color_Values;

Code_Color :: enum u8 {
    DEFAULT;
    COMMENT;
    TYPE;
    DIRECTIVE;
    KEYWORD;
    JUMP_KEYWORD;
    VALUE_KEYWORD;
    VALUE;
    FUNCTION;
    PUNCTUATION;
    STRING;
    ERROR;
    OPERATION;
    FORMAT_ITEM;
    HIGHLIGHT;

    CONSOLE_TEXT;
    CONSOLE_HEADER_TEXT;
    CONSOLE_ERROR;

    NUM_COLORS;
}

CODE_COLOR_MAP: [Code_Color.NUM_COLORS] Vector4;

refresh_code_color_map :: () -> [Code_Color.NUM_COLORS] Vector4 {
    using Code_Color;

    result: [NUM_COLORS] Vector4;

    result[DEFAULT]         = Colors.CODE_DEFAULT;
    result[COMMENT]         = Colors.CODE_COMMENT;
    result[DIRECTIVE]       = Colors.CODE_DIRECTIVE;
    result[TYPE]            = Colors.CODE_TYPE;
    result[FUNCTION]        = Colors.CODE_FUNCTION;
    result[PUNCTUATION]     = Colors.CODE_PUNCTUATION;
    result[STRING]          = Colors.CODE_STRING;
    result[VALUE]           = Colors.CODE_VALUE;
    result[JUMP_KEYWORD]    = Colors.CODE_JUMP;
    result[VALUE_KEYWORD]   = Colors.CODE_VALUE;
    result[ERROR]           = Colors.CODE_ERROR;
    result[KEYWORD]         = Colors.CODE_KEYWORD;
    result[OPERATION]       = Colors.CODE_OPERATION;
    result[FORMAT_ITEM]     = Colors.CODE_FORMAT_ITEM;
    result[HIGHLIGHT]       = Colors.CODE_HIGHLIGHT;

    result[CONSOLE_TEXT]    = Colors.CONSOLE_TEXT;
    result[CONSOLE_HEADER_TEXT] = Colors.CONSOLE_HEADER_TEXT;
    result[CONSOLE_ERROR]   = Colors.CONSOLE_ERROR;

    return result;
}


as_3_floats :: (color: Color) -> [3] float {
    result : [3] float = ---;
    result[0] = color.r;
    result[1] = color.g;
    result[2] = color.b;
    return result;
}

is_none :: (using color: Color) -> bool {
    return r < 0 || g < 0 || b < 0 || a < 0;
}


with_alpha :: (color: Color, alpha: float) -> Color {
    result := color;
    result.a = alpha;
    return result;
}

lerp :: (a: Color, b: Color, t: float) -> Color {
    result : Color = ---;
    result.r = lerp(a.r, b.r, t);
    result.g = lerp(a.g, b.g, t);
    result.b = lerp(a.b, b.b, t);
    result.a = lerp(a.a, b.a, t);
    return result;
}

brighten :: (a: Color, t: float) -> Color {
    return lerp(a, white, t);
}

white :: Color.{r = 1.0, g = 1.0, b = 1.0, a = 1.0};

convert_active_buffer_to_colors :: () {
    if editors.active < 0  return;

    builder : String_Builder;
    spaces :: "                                        ";

    editor := *open_editors[editors.active];
    buffer := *open_buffers[editor.buffer_id];

    s := cast(string) buffer.bytes;

    background_color : Color;

    do :: (name: string, keys: .. string, op : enum { none; darken; brighten; } = .none, bake := false, foreground := false) #expand {
        for key: keys {
            index := -key.count;
            found := false;
            while !found {
                index, found = first_index(s, key, index + key.count);
                if !found  break;
                if index > 0 && is_alnum(s[index - 1])
                || index + key.count < s.count -1 && is_alnum(s[index + key.count])
                    found = false;
            }
            if !found  continue;

            if foreground
                index, found = first_index(s, "\"foreground\"", index);
            if !found  continue;

            index, found = first_index(s, "\"#", index);
            if !found  continue;

            start := index + 2;
            end, found= := first_index(s, "\"", start);
            if !found  continue;

            hex := slice(s, start, end);

            if name == "background" {
                background_color = hex_to_color(hex);
            }

            if op {
                color := hex_to_color(hex);
                if op == .darken  color.a *= 0.5;
                else              color = brighten(color, 0.2);
                hex = color_to_hex(color, true);
            }

            if bake {
                color := hex_to_color(hex);
                color = lerp(background_color, with_alpha(color, 1.0), color.a);
                hex = color_to_hex(color, true);
            }

            print_to_builder(*builder, "%1:%2%3", name, slice(spaces, 0, 33 - name.count), temp_strings.upper(hex));
            if hex.count == 6  append(*builder, "FF");
            append(*builder, "\n");
            return;
        }

        hex := "FF00FFFF";
        print_to_builder(*builder, "%1:%2%3\n", name, slice(spaces, 0, 33 - name.count), temp_strings.upper(hex));
    }

    append(*builder, "[colors]\n");

    do("background",                     "editor.background");
    do("background_dark",                "sideBar.background", bake=true);
    do("background_highlight",           "statusBar.debuggingBackground", bake=true);
    do("background_light",               "titleBar.activeBackground", bake=true);
    do("background_bright",              "statusBar.background", op=.brighten, bake=true);
    do("background_region",              "editor.background");
    do("background_region_private",      "editor.background", bake=true);
    do("background_region_public",       "editor.background", bake=true);
    do("background_cursor_row",          "editor.lineHighlightBackground");
    append(*builder, "\n");
    do("selection_active",               "editor.selectionBackground");
    do("selection_inactive",             "editor.selectionBackground", op=.darken);
    do("selection_highlight",            "editor.selectionHighlightBackground");
    do("search_result_active",           "editor.findMatchBackground");
    do("search_result_inactive",         "editor.findMatchHighlightBackground");
    do("scrollbar",                      "scrollbarSlider.activeBackground");
    do("scrollbar_hover",                "scrollbarSlider.background");
    do("scrollbar_background",           "scrollbarSlider.background");
    do("cursor",                         "editorCursor.foreground");
    do("cursor_inactive",                "editorCursor.foreground");
    do("paste_animation",                "list.highlightForeground");
    do("splitter",                       "tab.inactiveBackground");
    do("splitter_hover",                 "tab.activeBackground");
    do("letter_highlight",               "editor.wordHighlightBackground");
    do("list_cursor_lite",               "list.highlightForeground");
    do("list_cursor",                    "list.activeSelectionBackground");
    do("shadow_dark",                    "panel.background", op=.darken);
    do("shadow_transparent",             "panel.background", op=.darken);
    do("text_input_label",               "editor.foreground");
    append(*builder, "\n");
    do("console_background",             "sideBar.background", bake=true);
    do("console_text",                   "source", "variable.other", "editor.foreground", foreground=true);
    do("console_header_text",            "source", "variable.other", "editor.foreground", foreground=true);
    do("console_header_background",      "statusBar.background", op=.brighten, bake=true);
    do("console_error",                  "inputValidation.errorBackground");
    append(*builder, "\n");
    do("zen_foreground",                 "source", "variable.other", "editor.foreground", foreground=true);
    do("zen_background",                 "editor.background");
    do("zen_margins",                    "sideBar.background", bake=true);
    do("zen_cursor",                     "editorCursor.foreground");
    do("zen_comment",                    "comment", "comment.line", "comment.block", foreground=true);
    append(*builder, "\n");
    do("ui_default",                     "button.foreground", "menu.foreground");
    do("ui_dim",                         "inputValidation.infoBackground", op=.darken);
    do("ui_neutral",                     "inputValidation.infoBackground");
    do("ui_message",                     "inputValidation.infoBackground");
    do("ui_warning",                     "inputValidation.warningBackground");
    do("ui_warning_dim",                 "inputValidation.warningBackground", op=.darken);
    do("ui_error",                       "inputValidation.errorBackground");
    do("ui_error_bright",                "inputValidation.errorBorder");
    do("ui_success",                     "ports.iconRunningProcessForeground");
    append(*builder, "\n");
    do("code_default",                   "source", "variable.other", "editor.foreground", foreground=true);
    do("code_comment",                   "comment", "comment.line", "comment.block", foreground=true);
    do("code_type",                      "support.class", "entity.name.class", "entity.name.type", "entity.name.namespace", "entity.name.scope-resolution", foreground=true);
    do("code_function",                  "entity.name.function", "meta.require", "support.function.any-method", foreground=true);
    do("code_punctuation",               "punctuation", foreground=true);
    do("code_operation",                 "keyword.operator", "punctuation", foreground=true);
    do("code_string",                    "string.quoted", "string.unquoted", "string", foreground=true);
    do("code_value",                     "constant.numeric", foreground=true);
    do("code_highlight",                 "meta.link", foreground=true);
    do("code_error",                     "invalid", "token.error-token", foreground=true);
    do("code_keyword",                   "keyword", foreground=true);
    do("code_jump",                      "keyword.control.jump", "keyword", foreground=true);
    do("code_directive",                 "keyword.other.directive", "keyword.other", foreground=true);
    do("code_format_item",               "punctuation.section.embedded", "variable.interpolation", foreground=true);
    append(*builder, "\n");

    output := builder_to_string(*builder);
    insert_string_at_offset(buffer, 0, output);

    cursor := leave_only_original_cursor(editor);
    cursor.pos = 0;
    cursor.col_wanted = 0;
    editor.cursor_moved = .jumped;
    cursor.sel = xx output.count;
}

update_colors_for_zen_mode :: (t: float) {
    raw_t := t;
    if zen_mode
        t *= cast(float)config.settings.zen_mode_blend_percent / 100.0;
    else
        t = 0;

    using Colors;
    BACKGROUND =                lerp(Loaded_Colors.BACKGROUND,                ZEN_BACKGROUND, t);
    BACKGROUND_DARK =           lerp(Loaded_Colors.BACKGROUND_DARK,           ZEN_BACKGROUND, t);
    BACKGROUND_HIGHLIGHT =      lerp(Loaded_Colors.BACKGROUND_HIGHLIGHT,      ZEN_BACKGROUND, t);
    BACKGROUND_LIGHT =          lerp(Loaded_Colors.BACKGROUND_LIGHT,          ZEN_BACKGROUND, t);
    BACKGROUND_BRIGHT =         lerp(Loaded_Colors.BACKGROUND_BRIGHT,         ZEN_BACKGROUND, t);
    BACKGROUND_REGION =         lerp(Loaded_Colors.BACKGROUND_REGION,         ZEN_BACKGROUND, t);
    BACKGROUND_REGION_PRIVATE = lerp(Loaded_Colors.BACKGROUND_REGION_PRIVATE, ZEN_BACKGROUND, t);
    BACKGROUND_REGION_PUBLIC =  lerp(Loaded_Colors.BACKGROUND_REGION_PUBLIC,  ZEN_BACKGROUND, t);
    BACKGROUND_CURSOR_ROW =     lerp(Loaded_Colors.BACKGROUND_CURSOR_ROW,     ZEN_BACKGROUND, t);

    //SELECTION_ACTIVE =          lerp(Loaded_Colors.SELECTION_ACTIVE,          ZEN_, t);
    //SELECTION_INACTIVE =        lerp(Loaded_Colors.SELECTION_INACTIVE,        ZEN_, t);
    //SELECTION_HIGHLIGHT =       lerp(Loaded_Colors.SELECTION_HIGHLIGHT,       ZEN_, t);
    //SEARCH_RESULT_ACTIVE =      lerp(Loaded_Colors.SEARCH_RESULT_ACTIVE,      ZEN_, t);
    //SEARCH_RESULT_INACTIVE =    lerp(Loaded_Colors.SEARCH_RESULT_INACTIVE,    ZEN_, t);
    //SCROLLBAR =                 lerp(Loaded_Colors.SCROLLBAR,                 ZEN_, t);
    //SCROLLBAR_HOVER =           lerp(Loaded_Colors.SCROLLBAR_HOVER,           ZEN_, t);
    //SCROLLBAR_BACKGROUND =      lerp(Loaded_Colors.SCROLLBAR_BACKGROUND,      ZEN_, t);

    CURSOR =                    lerp(Loaded_Colors.CURSOR,                    ZEN_CURSOR, raw_t * ifx zen_mode then 1.0 else 0.0);

    //CURSOR_INACTIVE =           lerp(Loaded_Colors.CURSOR_INACTIVE,           ZEN_, t);
    //PASTE_ANIMATION =           lerp(Loaded_Colors.PASTE_ANIMATION,           ZEN_, t);
    //SPLITTER =                  lerp(Loaded_Colors.SPLITTER,                  ZEN_, t);
    //SPLITTER_HOVER =            lerp(Loaded_Colors.SPLITTER_HOVER,            ZEN_, t);
    //LETTER_HIGHLIGHT =          lerp(Loaded_Colors.LETTER_HIGHLIGHT,          ZEN_, t);
    //LIST_CURSOR_LITE =          lerp(Loaded_Colors.LIST_CURSOR_LITE,          ZEN_, t);
    //LIST_CURSOR =               lerp(Loaded_Colors.LIST_CURSOR,               ZEN_, t);
    //SHADOW_DARK =               lerp(Loaded_Colors.SHADOW_DARK,               ZEN_, t);
    //SHADOW_TRANSPARENT =        lerp(Loaded_Colors.SHADOW_TRANSPARENT,        ZEN_, t);
    //TEXT_INPUT_LABEL =          lerp(Loaded_Colors.TEXT_INPUT_LABEL,          ZEN_, t);
    //MOTIF =                     lerp(Loaded_Colors.MOTIF,                     ZEN_, t);
    //COLLAPSED_AREA_MARKER =     lerp(Loaded_Colors.COLLAPSED_AREA_MARKER,     ZEN_, t);
    //GUTTER =                    lerp(Loaded_Colors.GUTTER,                    ZEN_, t);
    //CONSOLE_BACKGROUND =        lerp(Loaded_Colors.CONSOLE_BACKGROUND,        ZEN_, t);
    //CONSOLE_TEXT =              lerp(Loaded_Colors.CONSOLE_TEXT,              ZEN_, t);
    //CONSOLE_ERROR =             lerp(Loaded_Colors.CONSOLE_ERROR,             ZEN_, t);
    //CONSOLE_HEADER_BACKGROUND = lerp(Loaded_Colors.CONSOLE_HEADER_BACKGROUND, ZEN_, t);
    //CONSOLE_HEADER_SUCCESS =    lerp(Loaded_Colors.CONSOLE_HEADER_SUCCESS,    ZEN_, t);
    //CONSOLE_HEADER_ERROR =      lerp(Loaded_Colors.CONSOLE_HEADER_ERROR,      ZEN_, t);
    //CONSOLE_HEADER_TEXT =       lerp(Loaded_Colors.CONSOLE_HEADER_TEXT,       ZEN_, t);
    //UI_DEFAULT =                lerp(Loaded_Colors.UI_DEFAULT,                ZEN_, t);
    //UI_DIM =                    lerp(Loaded_Colors.UI_DIM,                    ZEN_, t);
    //UI_NEUTRAL =                lerp(Loaded_Colors.UI_NEUTRAL,                ZEN_, t);
    //UI_WARNING =                lerp(Loaded_Colors.UI_WARNING,                ZEN_, t);
    //UI_WARNING_DIM =            lerp(Loaded_Colors.UI_WARNING_DIM,            ZEN_, t);
    //UI_ERROR =                  lerp(Loaded_Colors.UI_ERROR,                  ZEN_, t);
    //UI_ERROR_BRIGHT =           lerp(Loaded_Colors.UI_ERROR_BRIGHT,           ZEN_, t);
    //UI_SUCCESS =                lerp(Loaded_Colors.UI_SUCCESS,                ZEN_, t);
    //UI_BACKGROUND_0 =           lerp( Loaded_Colors.UI_BACKGROUND_0,          ZEN_, t);
    //UI_BACKGROUND_1 =           lerp( Loaded_Colors.UI_BACKGROUND_1,          ZEN_, t);
    //UI_BACKGROUND_2 =           lerp( Loaded_Colors.UI_BACKGROUND_2,          ZEN_, t);
    //UI_BACKGROUND_3 =           lerp( Loaded_Colors.UI_BACKGROUND_3,          ZEN_, t);
    //UI_BACKGROUND_4 =           lerp( Loaded_Colors.UI_BACKGROUND_4,          ZEN_, t);
    //UI_BACKGROUND_5 =           lerp( Loaded_Colors.UI_BACKGROUND_5,          ZEN_, t);

    CODE_DEFAULT =              lerp(Loaded_Colors.CODE_DEFAULT,              ZEN_FOREGROUND, t);
    CODE_COMMENT =              lerp(Loaded_Colors.CODE_COMMENT,              ZEN_COMMENT, t);
    CODE_TYPE =                 lerp(Loaded_Colors.CODE_TYPE,                 ZEN_FOREGROUND, t);
    CODE_FUNCTION =             lerp(Loaded_Colors.CODE_FUNCTION,             ZEN_FOREGROUND, t);
    CODE_PUNCTUATION =          lerp(Loaded_Colors.CODE_PUNCTUATION,          ZEN_FOREGROUND, t);
    CODE_OPERATION =            lerp(Loaded_Colors.CODE_OPERATION,            ZEN_FOREGROUND, t);
    CODE_STRING =               lerp(Loaded_Colors.CODE_STRING,               ZEN_FOREGROUND, t);
    CODE_VALUE =                lerp(Loaded_Colors.CODE_VALUE,                ZEN_FOREGROUND, t);
    CODE_HIGHLIGHT =            lerp(Loaded_Colors.CODE_HIGHLIGHT,            ZEN_FOREGROUND, t);
    CODE_ERROR =                lerp(Loaded_Colors.CODE_ERROR,                ZEN_FOREGROUND, t);
    CODE_JUMP =                 lerp(Loaded_Colors.CODE_JUMP,                 ZEN_FOREGROUND, t);
    CODE_DIRECTIVE =            lerp(Loaded_Colors.CODE_DIRECTIVE,            ZEN_FOREGROUND, t);
    CODE_KEYWORD =              lerp(Loaded_Colors.CODE_KEYWORD,              ZEN_FOREGROUND, t);
    CODE_FORMAT_ITEM =          lerp(Loaded_Colors.CODE_FORMAT_ITEM,          ZEN_FOREGROUND, t);

    CODE_COLOR_MAP = refresh_code_color_map();
}