calculator_dialog_handle_event :: (event: Input.Event) -> handled: bool {
    using calculator_dialog;

    if event.type == .KEYBOARD && event.key_pressed {
        action, mapping := map_event_to_action(event, Action_Search_Dialog);
        if action == {
            case .move_right;              if maybe_add_space_to_end(input) return true;
            case .close_dialog;            close_calculator(); return true;
            case .open_entry_in_place;     #through;
            case .open_entry_on_the_side;  select_all(); return true;
        }

        handled := maybe_handle_text_input_event(*input, event);
        if handled  ficus_update_calculator_text(to_string(input.text));
        return handled;

    } else if event.type == .TEXT_INPUT {
        text_input_type_char(*input, event.utf32);
        ficus_update_calculator_text(to_string(input.text));
        return true;
    }

    return false;
}

toggle_calculator :: () {
    if active_global_widget == .calculator_dialog
        close_calculator();
    else
        show_calculator();
}

show_calculator :: () {
    active_global_widget = .calculator_dialog;

    using calculator_dialog;

    // Select text when opening
    input.cursor.sel = 0;
    input.cursor.pos = xx input.text.count;
}

close_calculator :: () {
    activate_editors();
}

calculator_result :: (is_error: bool, result: string) {
    replace_text(*calculator_dialog.output, result);
}

#scope_file

maybe_handle_text_input_event :: (using input: *Text_Input, event: Input.Event) -> handled: bool {
    input_text := copy_temporary_string(to_string(text));
    handled := text_input_handle_event(input, event);
    if handled
        return input_text != to_string(input.text);
    else
        return false;
}

maybe_add_space_to_end :: (input: Text_Input) -> bool {
    input_text := to_string(input.text);
    if !input_text
    || input.cursor.pos != input_text.count
    || input_text[input_text.count - 1] == #char " "
        return false;

    text_input_type_char(*input, cast(u32) #char " ");
    return true;
}

select_all :: () {
    calculator_dialog.input.cursor.pos = 0;
    calculator_dialog.input.cursor.sel = xx calculator_dialog.input.text.count;
}

#scope_export

calculator_dialog: Calculator_Dialog;

Calculator_Dialog :: struct {
    input: Text_Input;
    output: Text_Input;
}
