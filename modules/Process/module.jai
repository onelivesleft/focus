/*

   An API to start other programs in a cross-platform way.

 */

#if OS == .WINDOWS {
    #load "windows.jai";
} else #if OS == .LINUX || OS == .MACOS {
    #import "Basic";
    #import "POSIX";
    #load "posix.jai";
} else #if OS == .PS5 {
    #load "ps5.jai";
}

// The API to routines like run_command() takes arrays of strings (or, varargs strings,
// one for each argument). Why? Because it's the year 2022 and we still have stupid problems
// all the time with programs getting arguments wrong, because they didn't quote something
// and then shelled out, or whatever. Why does this keep happening? Because we are passing
// strings to these functions that execute commands. If we kept the arguments as an array,
// we could start whatever process we want with them and there is no added ambiguity
// or opportunity to parse things wrong.

// So, we made the forward-thinking decision that our APIs will be built around arrays
// of arguments, even if most operating systems currently give us sloppy APIs that use
// concatenated strings.

// So, it is best practice to store your command as separate arguments when possible.
// But sometimes it's not really possible, for example, you want to read a command
// from a text input widget, or as a line from a file.

// We provide this break_command_into_strings() to help you do this. Note that this
// function should probably be more robust; it allows you to quote arguments to put
// spaces inside, but it only looks for quotes at the start of an argument,
// it doesn't handle backslashed quotes, and so forth. As for what the rule should actually
// be, that makes sense across operating systems, if we can define it clearly it shouldn't
// be too hard to modify break_command_into_strings() to do the job.

break_command_into_strings :: (input: string) -> [..] string { // Array in temporary storage.
    String :: #import "String";

    t := input;

    result: [..] string;
    result.allocator = temp;

    while t.count {
        s := String.trim_left(t);
        if !s break;

        delimiter : u8 = #char " ";
        if s[0] == #char "\"" {
            advance(*s, 1);
            delimiter = #char "\"";
        }

        index := String.find_index_from_left(s, delimiter);
        if index == -1 {
            // If delimiter == ", This is a parse error. We will probably want a clean way to indicate this.
            array_add(*result, s);
            t = "";
        } else {
            t = advance(s, index+1);
            s.count = index;

            array_add(*result, String.trim_right(s));
        }
    }

    // For now we just deal with quotes.

    return result;
}

Process_Callback :: #type (s: string);

run_command :: (args: .. string, working_directory := "", capture_and_return_output := false, print_captured_output := false, timeout_ms := -1, arg_quoting := Process_Argument_Quoting.QUOTE_IF_NEEDED, output_callback : Process_Callback = null, error_callback : Process_Callback = null, enable_color := false) -> (process_result: Process_Result, output_string := "", error_string := "", timeout_reached := false) {
    process: Process;
    success := create_process(*process, .. args, working_directory, capture_and_return_output, arg_quoting, enable_color=enable_color);
    if !success    return .{type = .FAILED_TO_LAUNCH};

    defer deinit(*process);

    output_string: string;
    error_string : string;
    timeout_reached: bool;

    exit_timeout_ms := timeout_ms;
    if capture_and_return_output {
        output_builder: String_Builder;
        init_string_builder(*output_builder);
        error_builder : String_Builder;
        init_string_builder(*error_builder);

        start_time := current_time_monotonic();
        remaining_timeout_ms := timeout_ms;

        while true {
            output_buffer := ensure_contiguous_space_and_return_available_range(*output_builder);
            error_buffer := ensure_contiguous_space_and_return_available_range(*error_builder);
            success, output_bytes, error_bytes := read_from_process(*process, output_buffer, error_buffer, remaining_timeout_ms);

            if output_bytes {
                advance_through_ensured_space(*output_builder, output_bytes);
                if output_callback  output_callback(to_string(output_buffer.data, output_bytes));
                if print_captured_output {
                    new_data := to_string(output_buffer.data, output_bytes);
                    write_string(new_data, to_standard_error = false);
                }
            }
            if error_bytes {
                advance_through_ensured_space(*error_builder, error_bytes);
                if error_callback  error_callback(to_string(error_buffer.data, error_bytes));
                if print_captured_output {
                    new_data := to_string(error_buffer.data, error_bytes);
                    write_string(new_data, to_standard_error = true);
                }
            }

            if !success {
                log_error("Could not read output of command \"%\"", get_quoted_command_string(args));
                kill_process(*process);
                break;
            }

            if timeout_ms >= 0 {
                now := current_time_monotonic();
                remaining_timeout_ms = timeout_ms - to_milliseconds(now - start_time);

                if remaining_timeout_ms <= 0 {
                    // We’ve hit a timeout! Time to kill the child. (will be reaped below)
                    timeout_reached = true;
                    success := kill_process(*process);
                    if !success {
                        error_code, error_string := System.get_error_value_and_string();
                        log_error("Could not kill child for command \"%\": % %", get_quoted_command_string(args), error_code, error_string);
                    }
                    break;
                }
            }

            if process.output.eof && process.error.eof    break;
        }

        output_string = builder_to_string(*output_builder);
        error_string  = builder_to_string(*error_builder);
        exit_timeout_ms = -1;
    }

    process_result: Process_Result;
    exit_code: s32;
    while true {
        success, process_result = get_process_result(*process, exit_timeout_ms);
        if !success {
            error_code, error_string := System.get_error_value_and_string();
            log_error("Could not get process result for command \"%\": % %", get_quoted_command_string(args), error_code, error_string);
            kill_process(*process);
            process_result = .{type = .EXITED, exit_code = 1};
            break;
        }

        if process_result.type != .STILL_RUNNING     break;

        assert(exit_timeout_ms >= 0);
        exit_timeout_ms = -1;
        timeout_reached = true;
        // Kill process and then try to reap it again
        success = kill_process(*process);
        if !success {
            error_code, error_string := System.get_error_value_and_string();
            log_error("Could not kill child for command \"%\": % %", get_quoted_command_string(args), error_code, error_string);
            process_result = .{type = .EXITED, exit_code = 1};
            break;
        }
    }

    return process_result, output_string, error_string, timeout_reached;
}

Process :: struct {
    input:  Pipe;
    output: Pipe;
    error:  Pipe;

    #if OS == .WINDOWS {
        job_handle: HANDLE = INVALID_HANDLE_VALUE;
        info: PROCESS_INFORMATION;
    } else #if OS == .LINUX || OS == .MACOS {
        pid: pid_t;

        #if OS == .MACOS {
            kevent_queue: s32 = -1;
        }
    }

    Pipe :: struct {
        #if OS == .WINDOWS {
            handle: HANDLE = INVALID_HANDLE_VALUE;
            overlapped: *OVERLAPPED;
        } else {
            handle: s32 = -1;
        }
        eof: bool;
    }
}

// Windows passes arguments to applications as a single string and leaves the processing of those arguments
// up to the application.  The rules for decomposing the argument string into a list of discrete arguments
// is therefore application specific.  In the case of C and C++ applications, it is compiler specific.
// Since run_command takes a list of discrete arguments and composes a Windows argument string from them, we
// provide some support for automatically quoting individual arguments to keep them separate in the composed
// string.  That is the default behavior.  However, since the rules for decomposing arguments are application
// specific, it is impossible to automatically quote arguments in a way that works for every application.
// Therefore we also provide a NEVER_QUOTE operation so that arguments are passed unmodified to the
// application and the caller takes responsibility for quoting them if necessary.
// We're still thinking about the best way to provide a cross-platform abstaction that is convenient to use
// with both POSIX and Windows but doesn't restrict the caller from accessing the full capaibilites of either.
Process_Argument_Quoting :: enum {
    QUOTE_IF_NEEDED :: 0; // On Windows this will provide some automatic quoting of arguments with spaces.
    NEVER_QUOTE     :: 1; // If you want explicit control over the argument list, this will prevent any automatic quoting.
}

Process_Result_Type :: enum s32 {
    UNSTARTED;
    STILL_RUNNING;
    FAILED_TO_LAUNCH;
    EXITED;
    SIGNALED;
}

Process_Result :: struct {
    type: Process_Result_Type;
    exit_code: s32 = -1;
    signal: s32;
}

get_quoted_command_string :: (args: [] string, allocator := temp) -> string {
    // We may need to copy and quote arguments, so let's go heavyweight and do a String_Builder, though
    // we may not need it in most cases, I dunno man. Windows, please get a better API.
    builder: String_Builder;
    builder.allocator = allocator;
    for args {
        append_quoted(*builder, it);
        if it_index < args.count-1  append(*builder, " ");
    }

    return builder_to_string(*builder, allocator = allocator);
}

//
// This quoting routine is necessary because Windows' process launch API is so unfortunate.
// We haven't thought through what exactly needs to happen here, so this is a first approximation.
// Probably there is something in Windows somewhere that we might be able to consult to see what
// happens standardly.
// For now we detect whether the string contains ascii 32 or 34. If it doesn't, we just append
// the source string. If it does, we enclose the whole string in quotes, and then backslash
// any quotes inside those quotes.
append_quoted :: (builder: *String_Builder, s: string) {
    String :: #import "String";

    // May return s; may return a quoted copy of s in temporary storage.
    needs_quote := false;
    for 0..s.count-1 {
        c := s[it];
        if (c == #char " ") || (c == #char "\"") {
            needs_quote = true;
            break;
        }
    }

    if !needs_quote {
        append(builder, s);
        return;
    }

    append(builder, "\"");

    remainder := s;
    while 1 {
        String :: #import "String";
        // Now that we are quoting, we need to quote quotes.
        found, left, right := String.split_from_left(remainder, #char "\"");
        if !found break;

        append(builder, left);
        append(builder, "\\\"");

        remainder = right;
    }

    append(builder, remainder);
    append(builder, "\"");
}

#scope_module

System :: #import "System";
