In Workspace 2 ("Target Program"):
T:/TTS_LTS_Upgrade/Tools/modules/GUI/widgets/input_box.jai:37,24: Error: Procedure call did not match any of the possible overloads.

    input_box :: (input_box: *Input_Box, panel: *Panel, initial_text: string, color_proc : type_of(Input_Box.color_proc) = null, flags := Flags.NONE, tooltip := "", owner : *Widget = null) -> clicked: bool, *Input_Box {
        clicked, widget := _input_box(input_box, panel, flags, tooltip, initial_text, color_proc, owner);
                           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

T:/TTS_LTS_Upgrade/Tools/modules/GUI/widgets/input_box.jai:37,24: Possible overloads:

    _input_box :: (id: int, panel: *Panel, flags: Flags, tooltip: string, owner: *Widget, initial_text: string, color_proc: type_of(Input_Box.color_proc), owner: *Widget, callsite_key: u64) -> clicked: bool, *Input_Box {   (T:/TTS_LTS_Upgrade/Tools/modules/GUI/widgets/input_box.jai:71)
                  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

        Not enough arguments: Wanted 8, got 7.

    _input_box :: (input_box: *Input_Box, panel: *Panel, flags: Flags, tooltip: string, owner: *Widget, initial_text: string, color_proc: type_of(Input_Box.color_proc), owner: *Widget) -> clicked: bool, *Input_Box {   (T:/TTS_LTS_Upgrade/Tools/modules/GUI/widgets/input_box.jai:78)
                  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

        Mismatching levels of indirection. Type wanted: *Widget; type given: string
        T:/TTS_LTS_Upgrade/Tools/modules/GUI/widgets/input_box.jai:78,15: Info: ... in argument 5.

