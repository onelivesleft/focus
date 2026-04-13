PLATFORM_CONFIG_SECTION :: "[[windows]]";
PLATFORM_SUBSECTION_ENUM :: enum {}
PLATFORM_SUBSECTION_NAMES :: string.[];
Platform_Config :: struct {}

platform_parse_config_line :: (config: *Platform_Config, section: PLATFORM_SUBSECTION_ENUM, line: string) -> success: bool, error_msg: string {
    return true, "";
}

platform_apply_config :: inline (config: *Platform_Config) {
}

platform_copy_config :: (src: *Platform_Config, dst: *Platform_Config) {
}

platform_setup :: () {
    if timeBeginPeriod(1) != TIMERR_NOERROR then log_error("Couldn't set minimum timer resolution");
}

platform_data_dir :: () -> string {
    dir := trim_right(path_strip_filename(get_path_of_running_executable()), "/");
    return copy_string(dir);
}

platform_config_dir :: inline () -> string {
    return platform_data_dir();
}

platform_get_centered_window_dimensions :: (open_on_biggest: bool) -> s32, s32, s32, s32 {
    if !EnumDisplayMonitors(null, null, monitor_enum_proc, 0) then panic("Couldn't enumerate monitors");
    assert(monitors.count > 0, "Unexpectedly no monitors found. This is a bug.");

    monitor := monitors[0];

    if open_on_biggest {
        max_area := 0;
        for monitors {
            width  := it.right  - it.left;
            height := it.bottom - it.top;
            area   := width * height;
            if max_area < area {
                monitor  = it;
                max_area = area;
            }
        }
    } else {
        for monitors {
            if it.primary {
                monitor = it;
            }
        }
    }

    monitor_width  := monitor.right  - monitor.left;
    monitor_height := monitor.bottom - monitor.top;

    w := cast(s32) (monitor_width  / 1.5);
    h := cast(s32) (monitor_height / 1.5);
    x := cast(s32) (monitor.left + monitor_width  / 2 - w / 2);
    y := cast(s32) (monitor.top  + monitor_height / 2 - h / 2);

    return x, y, w, h;
}

normal_style : s32;

platform_create_window :: () {
    window = create_window(window_width, window_height, window_generic_title, window_x, window_y, background_color_rgb = as_3_floats(Colors.BACKGROUND), show = !FADE_IN_AT_STARTUP);
    #if REMOVE_TITLE_BAR {
        old_style := cast(s32) GetWindowLongW(window, GWL_STYLE);
        normal_style = old_style & ~cast(s32)(WS_CAPTION | WS_THICKFRAME);
        SetWindowLongW(window, GWL_STYLE, xx normal_style);
        SetWindowPos(window,null,0,0,0,0,SWP_NOZORDER|SWP_NOMOVE|SWP_NOSIZE|SWP_NOACTIVATE|SWP_FRAMECHANGED);
    }
    platform_set_border_color();
    #if FADE_IN_AT_STARTUP {
        platform_set_window_opacity(0.0, 0.0);
        UpdateWindow(window);
        ShowWindow(window, SW_SHOW);
    }

}

platform_set_window_location :: (x: s32, y: s32, w: s32, h: s32) {
    window_x = x;
    window_y = y;
    SetWindowPos(window, HWND_TOP, x, y, w, h, SWP_FRAMECHANGED);
    window_width, window_height = Simp.get_render_dimensions(window);
    screen = make_rect(0, 0, window_width, window_height);
}

platform_set_window_sizable :: (sizable: bool) {
    if sizable
        SetWindowLongW(window, GWL_STYLE, xx normal_style | xx (WS_THICKFRAME));
    else
        SetWindowLongW(window, GWL_STYLE, xx normal_style);
    SetWindowPos(window,null,0,0,0,0,SWP_NOZORDER|SWP_NOMOVE|SWP_NOSIZE|SWP_NOACTIVATE|SWP_FRAMECHANGED);
}

platform_start_sizing :: () {
    SC_SIZE :: 0xF000;
    DefWindowProcW(window, WM_SYSCOMMAND, SC_SIZE, 0);
}

platform_maximize_window :: (window: Window_Type) {
    ShowWindow(window, SW_MAXIMIZE);
}

platform_enable_drag_and_drop :: (window: Window_Type) {
    Windows.DragAcceptFiles(window, cast(Windows.BOOL) true);
}

platform_get_dpi_scale :: (window: Window_Type) -> float {
    #if WINDOWS7 {
        return 1.0;  // poor Windows 7 users
    } else {
        dpi := cast(float) GetDpiForWindow(window);
        return dpi / 96.0;
    }
}

platform_set_window_title :: (title: string) {
    SetWindowTextW(window, utf8_to_wide_new(title));
}

platform_wait_message :: inline () {
    WaitMessage();
}

platform_set_refresh_timer :: (window: Window_Type) {
    SetTimer(window, REFRESH_TIMER_ID, 50, cast(*void) 0);  // refresh every 50ms
}

platform_kill_refresh_timer :: (window: Window_Type) {
    KillTimer(window, REFRESH_TIMER_ID);
}

platform_enumerate_logical_drives :: () -> [] string {
    drives: [..] string;

    drives_buf: [500] u16;
    GetLogicalDriveStringsW(500, drives_buf.data);

    drive_wstr := drives_buf.data;
    for drives_buf {
        if it == 0 {
            drive, success := wide_to_utf8_new(drive_wstr);
            if !drive || !success break;
            drive.count -= 1;  // cut off separator
            array_add(*drives, drive);
            drive_wstr = *drives_buf[it_index + 1];
        }
    }

    return drives;
}

platform_get_save_file_name :: (file_name := "") -> string /* temp */, success: bool {
    buffer: [512] u16;

    // Clean the name from chars that Windows won't accept
    name := copy_temporary_string(file_name);
    replace_chars(name, "@$%&\\/:*?\"'<>|~`#^+={}[];!", cast(u8) #char "_");

    // Get the name to populate it in the filename box (convenient if we're resaving a deleted file)
    if name && name != "<new file>" {
        wide_name, success, length := utf8_to_wide_new(name);
        if success memcpy(buffer.data, wide_name, min(buffer.count, length));
    }

    ofn: OPENFILENAMEW;
    ofn.lStructSize = size_of(OPENFILENAMEW);
    ofn.hwndOwner   = window;
    ofn.lpstrFile   = buffer.data;
    ofn.nMaxFile    = buffer.count;
    ofn.lpstrTitle  = utf8_to_wide_new(tprint("Choose where to save '%'", name));
    ofn.Flags       = OFN_NOCHANGEDIR;

    for dir : project_dirs {
        if dir.path {
            ofn.lpstrInitialDir = utf8_to_wide_new(dir.path);
            break;
        }
    }

    // Since the filename box is blocking, the cursor will not update its visibility whilst it is open. Ensure it is visible first.
    platform_show_cursor(true);
    open_success := GetSaveFileNameW(*ofn);

    if open_success {
        file_path, success := wide_to_utf8_new(buffer.data);
        path_overwrite_separators(file_path, #char "/");

        if success {
            return file_path, success;
        }
    }
    return "", false;
}

platform_find_font_by_name :: (name: string, allocator := temp) -> bool, string {
    // We would like to use `EnumFontFamiliesExA()` so we can filter out fonts that are
    // not monospace. However it only enumerates fonts that have been loaded in GDI via
    // `AddFontResourceEx()` which doesn't include fonts installed in the user specific
    // location (`%LocalAppData\Microsoft\Windows\Fonts`) by default.
    //
    // Instead of spamming `AddFontResourceEx()` calls we just take file names straight
    // from he registry.

    hkeys  : []HKEY   = .[HKEY_CURRENT_USER, HKEY_LOCAL_MACHINE];
    styles : []string = .[" Regular", ""];
    types  : []string = .[" (TrueType)", ""];
    key    : string   = "Software\\Microsoft\\Windows NT\\CurrentVersion\\Fonts\0";  // Needs '\0' at the end so we can pass it to RegGetValueA()
    for hkey : hkeys {
        for style : styles {
            for type : types {
                buff: [1024]u8;
                size: DWORD = buff.count - 1;

                value := sprint("%1%2%3\0", name, style, type);  // Needs '\0' at the end so we can pass it to RegGetValueA()
                defer free(value);

                ret := RegGetValueA(hkey, key.data, value.data, RRF_RT_REG_SZ, null, buff.data, *size);
                if ret != 0 continue;

                path := to_string(buff.data, size);
                if !is_absolute_path(path) {
                    full_path := tprint("%/%", platform_get_fonts_dir(), path);
                    return true, copy_string(full_path,, allocator);
                }
                return true, copy_string(path,, allocator);
            }
        }
    }

    return false, "";
}

platform_get_fonts_dir :: () -> string {
    if !fonts_dir {
        path_utf16: *u16;
        ret := SHGetKnownFolderPath(*FOLDERID_Fonts, KF_FLAG_CREATE, null, *path_utf16);
        defer CoTaskMemFree(path_utf16);
        if SUCCEEDED(ret) {
            fonts_dir = copy_string(wide_to_utf8_new(path_utf16));
            path_overwrite_separators(fonts_dir, #char "/");
        } else {
            fonts_dir = "C:/Windows/Fonts";
        }
    }
    return fonts_dir;
}

platform_open_in_explorer :: (path: string, reveal := false) {
    path_backslashes := copy_string(path,, allocator = temp);
    path_overwrite_separators(path_backslashes, #char "\\");

    if reveal run_command("explorer", "/select,", path_backslashes);
    else      run_command("explorer", path_backslashes);
}

platform_path_equals :: (path_a: string, path_b: string) -> bool {
    return equal(path_a, path_b, ignore_case);
}

platform_normalize_path :: (path: string) -> string {
    builder: String_Builder;
    for split(path, u8.[#char "/", #char "\\"]) {
        if it == "."  continue;
        if it_index  append(*builder, "/");
        append(*builder, it);
    }
    return builder_to_string(*builder,, temp);
}

platform_path_contains :: inline (path: string, subpath: string) -> bool {
    return contains_nocase(path, subpath);
}

platform_set_border_color :: () {
    using DwmAttribute;
    col : u32 = 0xFFFFFFFF;
    if config.settings.colored_titlebar {
        background := Colors.BACKGROUND;
        r : u32 = cast(u32)(background.r * 255.0);
        g : u32 = cast(u32)(background.g * 255.0);
        b : u32 = cast(u32)(background.b * 255.0);
        // COLORREF format is 0x00bbggrr
        col = 0x00000000;
        col |= b << 16;
        col |= g << 8;
        col |= r;
    }
    DwmSetWindowAttribute(window, CAPTION_COLOR, *col, size_of(u32));

    darkmode := ifx config.settings.dark_titlebar then 1 else 0;
    DwmSetWindowAttribute(window, USE_IMMERSIVE_DARK_MODE , *darkmode, size_of(type_of(darkmode)));
}

#scope_file
last_set_opacity: u8 = 255;
#scope_export

platform_set_window_opacity :: (opacity: float, min_opacity := 0.1) {
    // WARNING! If you set the opacity too low you will make it very hard for the user to interact with your program!
    // Leave the min_opacity alone unless you really mean it.

    #if OS == .WINDOWS {
        clamped := clamp(opacity, min_opacity, 1.0);
        a := cast(u8) clamp(clamped * 256, 0, 255);
        if last_set_opacity == a
            return;

        if a < 255 {
            if last_set_opacity == 255 {
                extended_style := GetWindowLongW(window, GWL_EXSTYLE);
                extended_style |= WS_EX_LAYERED;
                SetWindowLongW(window, GWL_EXSTYLE, extended_style);
            }
            LWA_ALPHA :: 2;
            user32 :: #system_library "user32";
            SetLayeredWindowAttributes :: (hwnd: *void, crKey: u32, bAlpha: u8, dwFlags: u32) -> bool #foreign user32;
            SetLayeredWindowAttributes(window, 0, a, LWA_ALPHA);
        }
        else { // We must have been translucent to get here, so just remove the style that enables opacity.
            extended_style := GetWindowLongW(window, GWL_EXSTYLE);
            extended_style &= ~cast(s32)WS_EX_LAYERED;
            SetWindowLongW(window, GWL_EXSTYLE, extended_style);
        }

        last_set_opacity = a;
    }
}

platform_show_cursor :: (show: bool) {
    if show {
        if cursor_shown <= 0
            cursor_shown = ShowCursor(1);
    } else {
        while cursor_shown >= 0 {
            cursor_shown = ShowCursor(0);
        }
    }
}


single_instance_pipe_name: *u16;
single_instance_mutex_name: *u16;
single_instance_mutex: HANDLE;
single_instance_pipe: HANDLE;
single_instance_mode : enum { NONE; CLIENT; SERVER; } = .NONE;
single_instance_buffer: [] u8;
single_instance_buffer_size : u32 : 2048;

Single_Instance_Message : enum u8 {
    FILENAME;
    LINE;
    COLUMN;
}


platform_handle_single_instance :: (name: string, name_index: int, command_line_arguments: [] string) {
    assert(name != "");
    single_instance_mutex_name = utf8_to_wide_new(tprint("Global\\onelivesleft.focus.%", name));
    single_instance_pipe_name = utf8_to_wide_new(tprint("\\\\.\\pipe\\onelivesleft.focus.%", name));

    single_instance_mutex = CreateMutexW(null, 1, single_instance_mutex_name);
    if !single_instance_mutex {
        error := GetLastError();
        log_error("Failed to create or get mutex for single-instance mode.\n%\n", error);
        exit(1);
    }

    if GetLastError() == ERROR_ALREADY_EXISTS {
        // Failed to create the mutex, so we are a client; send the requested file+position to the server and exit.
        // In single-instance client mode, the only command line arguments accepted are a single filename,
        // an optionl line number, an optional column number, (and of course the `-single <name>`)

        single_instance_pipe = CreateFileW(single_instance_pipe_name, GENERIC_WRITE, 0, null, OPEN_EXISTING, 0, null);
        if single_instance_pipe == INVALID_HANDLE_VALUE {
            error := GetLastError();
            log_error("Failed to create pipe for single-instance client mode.\n%\n", error);
            exit(2);
        }

        path := "";
        coords := Coords.{-1, -1};

        for command_line_arguments {
            if it_index == 0 || it_index == name_index || it_index == name_index - 1
                continue;

            if is_digit(it[0]) {
                if coords.line == -1
                    coords.line = cast(s32) parse_int(*it) - 1;
                else if coords.col == -1
                    coords.col = cast(s32) parse_int(*it) - 1;
            }
            else if !path {
                path = it;
            }
        }

        message: *u8;
        message_size: u32;

        if path {
            message_size = size_of(Coords) + size_of(s32) + cast(u32)path.count + 1;
            message = alloc(message_size);

            head := cast(*s32) message;
            head.* = coords.line;
            head += 1;
            head.* = coords.col;
            head += 1;
            head.* = cast(s32) path.count;
            head += 1;
            s := cast(*u8) head;
            memcpy(s, path.data, path.count);
        }
        else {
            message_size = size_of(Coords) + size_of(u32);
            message = alloc(message_size);
        }

        bytes_written: u32;
        if !WriteFile(single_instance_pipe, message, message_size, *bytes_written, null) {
            error := GetLastError();
            log_error("Failed to write to pipe in single-instance client mode.\n%\n", error);
            exit(3);
        }

        exit(0);
    }
    else {
        // No error creating the mutex, so we are the server.
        single_instance_pipe = CreateNamedPipeW(single_instance_pipe_name, PIPE_ACCESS_INBOUND|FILE_FLAG_OVERLAPPED, PIPE_TYPE_MESSAGE|PIPE_READMODE_MESSAGE|PIPE_WAIT, 1, 0, single_instance_buffer_size, 0, null);
        if single_instance_pipe == INVALID_HANDLE_VALUE {
            error := GetLastError();
            log_error("Failed to create pipe for single-instance server mode.\n%\n", error);
            exit(4);
        }

        single_instance_mode = .SERVER;
        single_instance_buffer = NewArray(single_instance_buffer_size, u8);
        print("Started in single-instance mode with name [%]\n", name);
    }
}


platform_update_for_single_instance :: () {
    if single_instance_mode == .NONE  return;
    assert(single_instance_mode == .SERVER);

    count: u32;
    success := PeekNamedPipe(single_instance_pipe, null, 0, null, *count, null) != 0;
    if !success || !count  return;

    defer {
        DisconnectNamedPipe(single_instance_pipe);
        CloseHandle(single_instance_pipe);
        single_instance_pipe = CreateNamedPipeW(single_instance_pipe_name, PIPE_ACCESS_INBOUND|FILE_FLAG_OVERLAPPED, PIPE_TYPE_MESSAGE|PIPE_READMODE_MESSAGE|PIPE_WAIT, 1, 0, single_instance_buffer_size, 0, null);
        if single_instance_pipe == INVALID_HANDLE_VALUE {
            error := GetLastError();
            log_error("Failed to recreate pipe for single-instance server mode.\n%\n", error);
        }
    }

    success = ReadFile(single_instance_pipe, single_instance_buffer.data, single_instance_buffer_size, *count, null) != 0;
    if !success || !count { // if peek count was > 0 then this one should be too!
        error := GetLastError();
        log_error("Error reading single-instance pipe: %\n", error);
        return;
    }

    path : string = ---;
    coords: Coords;

    head := single_instance_buffer.data;
    coords.line = (cast(*s32)head).*;
    head += 4;
    coords.col = (cast(*s32)head).*;
    head += 4;
    character_count : s32 = (cast(*s32)head).*;
    head += 4;

    if character_count {
        path.data = head;
        path.count = character_count;
        head += character_count;
        print("single-instance-request: line=% col=% path=%\n", coords.line, coords.col, path);
        jump_to_file_coord(path, coords);
    }
    else {
        print("single-instance-request: no path\n");
    }

    single_instance_buffer.data = head;
    focus_focus();
}


platform_focus_focus :: () {
    SetForegroundWindow(window);
}


#scope_file


cursor_shown : s32 = 1;
fonts_dir: string;

monitor_enum_proc :: (hMonitor: HMONITOR, hdc: HDC, rect: *RECT, data: LPARAM) -> BOOL #c_call {
    monitor : Monitor = ---;
    monitor.left   = rect.left;
    monitor.top    = rect.top;
    monitor.right  = rect.right;
    monitor.bottom = rect.bottom;

    monitorInfo: MONITORINFO;
    monitorInfo.cbSize = size_of(MONITORINFO);

    GetMonitorInfoW(hMonitor, *monitorInfo);
    monitor.primary = !!(monitorInfo.dwFlags & 0x1);

    new_context : Context;
    push_context new_context {
        array_add(*monitors, monitor);
    }

    return xx true;
}

Monitor :: struct {
    left   : int;
    top    : int;
    right  : int;
    bottom : int;
    primary: bool;
};

monitors : [..] Monitor;

REFRESH_TIMER_ID :: 0;

user32   :: #system_library "user32";
kernel32 :: #system_library "kernel32";
shell32  :: #system_library "shell32";
ole32    :: #system_library "ole32";

KF_FLAG_CREATE :: 0x00008000;                                       // https://learn.microsoft.com/en-us/windows/win32/api/shlobj_core/ne-shlobj_core-known_folder_flag
FOLDERID_Fonts :: #run uid("FD228CB7-AE11-4AE3-864C-16F3910AB8FE"); // https://learn.microsoft.com/en-us/windows/win32/shell/knownfolderid

WaitMessage :: () -> s32 #foreign user32;
SetTimer  :: (hWnd: HWND, nIDEvent: u64, uElapse: u32, lpTimerFunc: *void) -> s32 #foreign user32;
KillTimer :: (hWnd: HWND, nIDEvent: u64) -> bool #foreign user32;
GetDpiForWindow :: (hWnd: HWND) -> u32 #foreign user32;
GetLogicalDriveStringsW :: (nBufferLength: DWORD, lpBuffer: *u16) -> DWORD #foreign kernel32;
ShellExecuteW :: (hwnd: HWND, lpOperation: *u16, lpFile: *u16, lpParameters: *u16, lpDirectory: *u16, nShowCmd: int) -> s32 #foreign shell32;
SHGetKnownFolderPath :: (nFolder: REFGUID, dwFlags: DWORD, hToken: HANDLE, pszPath: **u16) -> HRESULT #foreign shell32;
CoTaskMemFree :: (pv: *void) #foreign ole32;
SetForegroundWindow :: (hwnd: HWND) -> s32 #foreign user32;
CreateMutexW :: (lpMutexAttributes: *void, bInitialOwner: BOOL, lpName: *u16) -> HANDLE #foreign kernel32;
DisconnectNamedPipe :: (pipeHandle: HANDLE) #foreign kernel32;

PIPE_TYPE_MESSAGE :: 4;
PIPE_READMODE_MESSAGE :: 2;
PIPE_WAIT :: 0;


#import "Windows";
#import "Windows_Registry";
#import "Process";

Dwmapi :: #system_library "Dwmapi";
DwmSetWindowAttribute :: (handle: HANDLE, dwAttribute: DwmAttribute, pvAttributde :*void, cbAttribute :DWORD) -> HRESULT #foreign Dwmapi;

DwmAttribute :: enum u32 {
  NCRENDERING_ENABLED;
  NCRENDERING_POLICY;
  TRANSITIONS_FORCEDISABLED;
  ALLOW_NCPAINT;
  CAPTION_BUTTON_BOUNDS;
  NONCLIENT_RTL_LAYOUT;
  FORCE_ICONIC_REPRESENTATION;
  FLIP3D_POLICY;
  EXTENDED_FRAME_BOUNDS;
  HAS_ICONIC_BITMAP;
  DISALLOW_PEEK;
  EXCLUDED_FROM_PEEK;
  CLOAK;
  CLOAKED;
  FREEZE_REPRESENTATION;
  PASSIVE_UPDATE_MODE;
  USE_HOSTBACKDROPBRUSH;
  USE_IMMERSIVE_DARK_MODE :: 20;
  WINDOW_CORNER_PREFERENCE :: 33;
  BORDER_COLOR;
  CAPTION_COLOR;
  TEXT_COLOR;
  VISIBLE_FRAME_BORDER_THICKNESS;
  SYSTEMBACKDROP_TYPE;
  LAST;
}
