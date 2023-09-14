icon_search_dialog_handle_event :: (event: Input.Event) -> handled: bool {
    using icon_search_dialog;

    if event.type == .KEYBOARD && event.key_pressed {
        action, mapping := map_event_to_action(event, Action_Open_File_Dialog);
        if action == {
            case .close_dialog;             hide_icon_search_dialog();     return true;
            //case .open_entry_in_place;      open_selected_project();        return true;
            //case .open_entry_on_the_side;   open_selected_project();        return true;

            case .move_up;                  move_cursor(-1, wrap = true);   return true;
            case .move_down;                move_cursor( 1, wrap = true);   return true;
            case .move_up_fast;             move_cursor(-5);                return true;
            case .move_down_fast;           move_cursor( 5);                return true;
            case .move_up_one_page;         move_cursor(-per_page);         return true;
            case .move_down_one_page;       move_cursor( per_page);         return true;
        }

        handled := maybe_handle_text_input_event(*input, event);
        return handled;

    } else if event.type == .TEXT_INPUT {
        char := event.utf32;
        if char == 127 return true;  // there seems to be a bug in the Input module
                                // which generates a TEXT_INPUT event for DEL
                                // when Ctrl+Backspace is pressed

        text_input_type_char(*icon_search_dialog.input, char);
        refresh_entries();
        return true;
    }
    return false;
}

show_icon_search_dialog :: () {
    active_global_widget = .icon_search_dialog;

    text_input_fully_clear(*icon_search_dialog.input);

    refresh_entries();
}

hide_icon_search_dialog :: () {
    activate_editors();
}

#scope_file

refresh_entries :: () {
    using icon_search_dialog;

    array_reset_keeping_memory(*filtered);

    scroll_to_cursor = .snap;
    scroll_y = 0;
    selected = 0;

    input_string := to_string(input.text);
    filter_chars := decode_utf8_string_to_temp_char_substrings(input_string);

    icon_table := get_icon_lookup_table();
    for icon, name : icon_table {
        //score, highlights := fuzzy_match(name, filter_chars, input_string);
        //if score < 0 continue;
        index, found := first_index(name, input_string);
        if !found  continue;

        highlights := NewArray(name.count, bool, initialized = true);
        for 0 .. input_string.count - 1
            highlights[it + index] = true;

        entry := array_add(*filtered);
        entry.name = name;
        entry.highlights = highlights;
        entry.sort_key = xx index;
        //entry.sort_key = cast(u64) score;
    }

    compare_entries :: (e1: Entry, e2: Entry) -> s64 {
        key_diff := cast,no_check(s64) e2.sort_key - cast,no_check(s64) e1.sort_key;
        if key_diff != 0 return key_diff;
        return memcmp(e1.name.data, e2.name.data, min(e1.name.count, e2.name.count));
    }

    quick_sort(filtered, compare_entries);
}

move_cursor :: (delta: s64, wrap := false, snap := true) {
    using icon_search_dialog;

    selected += delta;

    if wrap {
        if selected < 0 then selected = max(0, filtered.count - 1);
        if selected >= filtered.count then selected = 0;
    } else {
        if selected < 0 then selected = 0;
        if selected >= filtered.count then selected = filtered.count - 1;
    }
    scroll_to_cursor = ifx snap then Scroll_Mode.snap else .yes;
}

maybe_handle_text_input_event :: (using input: *Text_Input, event: Input.Event) -> handled: bool {
    input_text := copy_temporary_string(to_string(text));
    handled := text_input_handle_event(input, event);
    if handled {
        if input_text != to_string(input.text) then refresh_entries();
        return true;
    }
    return false;
}


#scope_export

icon_search_dialog: Icon_Search_Dialog;


#scope_file

Icon_Search_Dialog :: struct {
    input: Text_Input;
    filtered: [..] Entry;
    selected: s64;
    selected_by_mouse: s64 = -1;  // to remember which entry the left mouse button went down on

    scroll_y: s32;
    scroll_anim := #run Tween_Animation(s32).{ speed = xx 0.1, func = .lerp };
    per_page: s64 = 10;

    scroll_to_cursor: Scroll_Mode = .no;
};

Entry :: struct {
    name: string;
    highlights: [] bool;
    sort_key: u64;
}
