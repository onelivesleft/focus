# This is a fork of Focus

This is not [the official version of Focus](https://github.com/focus-editor/focus/), this is a highly personalised fork of it; it may be to your taste, or it may not.  Maybe you would prefer a more standardized editor: if you don't like this version then check out the official one (if you haven't already).

## How this fork is different:

In a lot of ways! Some big, some small:

* Added setting `can_cancel_go_to_line` - hitting escape after typing the number leaves you at the destination, instead of taking you back to where you were.
* Added commands `center_viewport_on_cursor` and `dump_key_mappings`
* Reworked Editor History
* Added `create_cursors_around` - will add cursors above and below your current cursor, for all the lines above and below which are long enough to have a cursor at that position.
* Eye tracking for tobii eye-tracking devices.
* Buffer switcher - `move_to_previous_buffer` & `move_to_next_buffer`, usually bound to ctrl-tab / ctrl-shift-tab.
* Autoindent as you type for braced languages
* Jump to matching bracket - `jump_to_matching_bracket`
* Settings `ignore_whitespace_in_finder` & `ignore_whitespace_in_search_bar` - make space behave as a simple wildcard in searches (less useful now Focus has regex)
* Text is only copied to the clipboard when you use `copy` or `cut` (you don't magically trash your clipboard while deleting text)
* Config allows you to type a numeric keycode instead of a keycode name.  If you want to bind a key but don't know what it's called, use the `Toggle Show Keystrokes` command to find out it's keycode, and enter the number directly. For example, `Ctrl-96  toggle_console`
* `Show Icon Search` command, which lets you search through icons available for drawing in Focus.  Useful for Focus devs, and perhaps if you want to use an icon in a Ficus script.
* Added `change_case_to_upper`, `change_case_to_lower`, `change_case_to_caps`, `change_case_cycle`.
* Added `hide_current_buffer` command: equivalent to closing the current tab in other editors.
* Added "Convert Current Buffer To [colors]" to generate theme from vscode theme json: paste json from your vscode into a buffer then run this command to convert it to a Focus setting equivalent (roughly).
* Change window title to show project first (so when you look at theOS task bar you have a better idea of what to click on)
* Improved word jump / select word.
* Added cursor row highlight (now also present in main fork, but this one is prettier!).  Control color with `background_cursor_row` setting.
* Adding cursor above/below now skips blank lines.
* Added `show_cursor_position` command.
* Added `toggle_show_keystrokes` command.

Toggle Show Filename
Update TODO.md
Update TODO.md
Experimental whitespace collapse
Merge branch 'main' of https://github.com/onelivesleft/focus
Merge main
SKIP_CUTSCENES
Fix jump to matching bracket not working at end of file
Draw #scope transitions as tabs
Added Quit command
Collapse leading whitespace
Prettier collapsed whitspace marker
Pretty.  Draggable splash screen.
Profiling (Iprof), icon search panel now copies icon string to clipboard
Better whitespace collapse mode marker
Merge branch 'main' of https://github.com/onelivesleft/focus
Working after merge main
Fix toast start position
Only eyetrack while application is active
Profile modules, profile graph, fixed regexp
Fig �
Ficus! �  Hide Iprof build messages, Fix buffer info arrays, Fix buffer.dirty draw crash,
Premerge
Merge branch 'main' of https://github.com/onelivesleft/focus
Merge main
Fix scroll clamp
Ficus Turing complete!, Improved console, Iprof jump to row,
Fixed console font, prettier console / iprof
Convert Buffer bools to Buffer.flags
Much prettier console
Fix fonts, configurable console font size, prettier console
New build system, Remove old build system, Open Console Buffer, Fix jump to source location, Better fuzzy matching
Fixed finder lag, Ficus keybinds
Fix console not hiding after successful build
Fix console build animation
Bold text, Fix console colors, Console UI, Fix eye tracking lag (thanks Philip!)
Ficus++, first.jai now errors out instantly if the target exe is write-locked, Fixed delete actions erroneously copying to clipboard
Fix no-file buffer sticking around after save-as
Error descriptors at error, jump_to_previous_error, source location buttons in console, maximize console,
Fix console output not buffering, Restore default version of Strings module (its threading support is bad, but will work OK with how Focus uses threads)
Clear Build Errors command
Reverted Strings change, Ficus++
Fix region coloring, Ficus++
Fix open_console_buffer / save_as on console buffer
Start of rework Ficus to run async
Ficus++ (now has own state machine)
Start of Ficus debugging
Fix decorated buffer using a raw pointer, fix save_all saving unmodified files
Merge branch 'main' of https://github.com/onelivesleft/focus
Merge main
Fix up merge
Fix save_all
Simple Changelist, Fix delete_to_start/end copying to clipboard, Fix buffers not saving on build
Ficus breakpoints (almost)
Ficus debugging with UI, Status bar, window_location instruction to get/set window
Merge branch 'main' of https://github.com/onelivesleft/focus
Merge main
Dev build includes iprof, other builds do not
Fix show icon search
Ficus: Decorate current instruction, fix jumps.
Fixed build options at top of main: can now disable them to get back default Focus look
Zen mode
(HEAD -> main, origin/main, origin/HEAD) Reworked User Messages





### Parsing
* Added Markdown parsing
* Parsing works on document sections as well as entire documents. i.e. You can embed a Jai string inside a Markdown document code block and have it colored correctly.
* Documents are given Section delimiters you can easily jump to. These are split into important (i.e. H1/H2 in Markdown, #scope_ declarations in jai) or regular (All headers in Markdown, procedure declarations in Jai).  Jump between them with `move_up_one_section`, `move_down_one_section`, `move_up_one_important_section`, `move_down_one_important_section`.

### Look & Feel
* Remove title bar / standard Windows gadgets (behaves more like a fullscreen window).  You can move the window around by dragging the file tab in the top right.  If you're not using a window layout manager (like FancyZones in PowerToys) you can resize by right-clicking it, selecting `Size` and then hitting arrow keys. You can revert back to a normal by turning off some bool constants at the top of `main.jai`
* You can set the size and position of the window via Ficus script: run `window_location? print` to see the current dimensions (x, y, w, h), and in your `on_load` script use `<x> <y> <w> <h> window_location!`
* Decorations: graphical elements added within the text, For instance, color squares drawn next to color settings in config files.

### Jai specific features
* Simple goto definition - `jump_to_definition`. Requires you to turn on the settings `ignore_whitespace_in_finder` & `ignore_whitespace_in_search_bar`
* Scope regions: background color is changed depending on whether you are in `#scope_file`, `#scope_module` or `#scope_export`
* Compile-time regions: background color is changed for various compile time sections of code, to make it easier to see what the generated code looks like.
* Error parsing on build, cycle through errors with `jump_to_error`, `jump_to_previous_error`, clear them by building again or with `clear_build_errors`
* Added jump to added string source / jump to comments source location

![Compile-time code regions](imagesa/compile_time_region.png)



### Ficus

### Build

### Console
* Floating editor window which shows info / output from operations (such as builds)

