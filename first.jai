VERSION      :: "0.2.0-dev";
RELEASE_DATE :: #run -> string {
    current_time := to_calendar(current_time_consensus());
    return calendar_to_string(current_time);
}

include_profiling := false;
include_profiling_modules := true;
no_output := false;

#run build();

build :: () {
    context.logger = logger;

    options := get_build_options();
    options.minimum_macos_version = .{12, 0};
    args := options.compile_time_command_line;

    import_path: [..] string;
    array_add(*import_path, "modules");
    array_add(*import_path, ..options.import_path);
    options.import_path = import_path;

    set_build_options_dc(.{do_output=false});
    set_working_directory(#filepath);

    optimized := false;
    windows7  := false;
    set_optimization(*options, .DEBUG);
    // options.arithmetic_overflow_check = .FATAL; Try uncommenting this line in 0.1.072. Doesn't work correctly on 0.1.071.
    build_dir := "build_debug";
    options.output_executable_name = "focus";
    dev_build := false;

    for arg: args {
        if arg == {
          case "release";
            optimized = true;
            build_dir = "build_release";
            set_optimization(*options, .VERY_OPTIMIZED);
            options.llvm_options.enable_split_modules = false;
            options.array_bounds_check = .ON;
            options.null_pointer_check = .ON;
            options.arithmetic_overflow_check = .OFF;
            include_profiling = false;
          case "debug";
          case "dev";
            include_profiling = true;
            build_dir = ".";
            options.output_executable_name = "focus_dev";
            dev_build = true;
          case "no_output";
            no_output = true;
            include_profiling = false;
          case "windows7";
            windows7 = true;
            options.output_executable_name = "focus_windows7";
          case;
            compiler_report(tprint("Command-line argument #%, '%', is invalid. Valid options are: 'debug', 'release'.\n", it_index+1, arg));
        }
    }

    if !no_output {
        options.output_path = build_dir;
        make_directory_if_it_does_not_exist(build_dir);

        if !optimized && !dev_build
            options.output_executable_name = sprint("%_debug", options.output_executable_name);

        #if OS == .WINDOWS {
            slash :: "\\";
            exe :: ".exe";
        }
        else {
            slash :: "/";
            exe :: "";
        }
        output_path := tprint("%1%2%3%4%5", #filepath, options.output_path, slash, options.output_executable_name, exe);
        if !dev_build {
            handle, exists := file_open(output_path);
            if exists {
                file_close(*handle);
                if !file_delete(output_path) {
                    print("Could not write to output executable: %\n", output_path, to_standard_error = true);
                    exit(1);
                }
            }
        }
    }

    w := compiler_create_workspace(options.output_executable_name);
    set_build_options(options, w);
    #if OS == .WINDOWS {
        // Disable runtime console
        if optimized {
            set_build_options_dc(.{append_linker_arguments=.["/SUBSYSTEM:windows", "/ENTRY:mainCRTStartup"]}, w);

            // For tracing release builds use this:
            // set_build_options_dc(.{append_linker_arguments=.["/SUBSYSTEM:windows", "/ENTRY:mainCRTStartup", "ws2_32.lib", "msvcprtd.lib"]}, w);
        } else {
            set_build_options_dc(.{append_linker_arguments=.["ws2_32.lib", "msvcprtd.lib"]}, w);
        }
    }
    if no_output  set_build_options_dc(.{do_output = false}, w);

    plugins: [..] *Metaprogram_Plugin;
    intercept_flags: Intercept_Flags;
    no_iprof : Metaprogram_Plugin;
    iprof := *no_iprof;
    if include_profiling {
        init_plugins(string.["Iprof"], *plugins, w);
        iprof = plugins[0];
        if include_profiling_modules
            iprof.handle_one_option(iprof, .["-modules"], 0);
    }
    else {
        init_plugins(string.[], *plugins, w);
    }

    if iprof.before_intercept  iprof.before_intercept(iprof, *intercept_flags);

    compiler_begin_intercept(w);

    if iprof.add_source  iprof.add_source(iprof);

    add_build_file("src/main.jai", w);

    build_constants := tprint(#string STRING
            VERSION      :: "%";
            RELEASE_DATE :: "%";
            DEBUG        :: %;
            WINDOWS7     :: %;
            IPROF        :: %;
        STRING,
            VERSION,
            RELEASE_DATE,
            ifx optimized then "false" else "true",
            ifx windows7  then "true"  else "false",
            include_profiling,
    );
    add_build_string(build_constants, w);

    config_refresh_procs : [..] string;
    inserted_config_refresh_procs := false;
    successful := true;

    while true {
        message := compiler_wait_for_message();
        if message.workspace != w continue;

        if iprof.message  iprof.message(iprof, message);

        if message.kind == {
            case .TYPECHECKED;
            typechecked := cast(*Message_Typechecked) message;
            for tc: typechecked.procedure_headers {
                header := tc.expression;
                if has_note(header, "OnConfigRefresh") {
                    //print("Found OnConfigRefresh proc: %\n", header);
                    array_add(*config_refresh_procs, header.name);
                }
            }

            case .PHASE;
            phase := cast(*Message_Phase) message;
            if phase.phase == .TYPECHECKED_ALL_WE_CAN {
                if inserted_config_refresh_procs  continue;
                inserted_config_refresh_procs = true;
                builder : String_Builder;
                append(*builder, "run_config_refresh_hooks :: () {\n");
                for config_refresh_procs {
                    append(*builder, "    ");
                    append(*builder, it);
                    append(*builder, "();\n");
                }
                append(*builder, "}\n");
                add_build_string(builder_to_string(*builder), message.workspace);
            }
            else if no_output && phase.phase == .ALL_TARGET_CODE_BUILT {
                exit(0);
            }

            case .COMPLETE;
                break;

            case .ERROR;
                successful = false;
                break;
        }
    }

    compiler_end_intercept(w);

    if iprof.finish    iprof.finish(iprof);
    if iprof.shutdown  iprof.shutdown(iprof);

    if !successful  return;

    #if OS == .WINDOWS {
        exe_path := tprint("%/%.exe", build_dir, options.output_executable_name);

        ico_data := create_ico_file_from_bitmap_filename("images/focus.png");
        success := set_icon_by_data(exe_path, ico_data);
        if !success {
            log_error("ERROR: Couldn't set icon for '%'\n", exe_path);
        }

        manifest_options: Manifest_Options;
        success = add_manifest_to_executable(exe_path, manifest_options);
        if !success {
            log_error("ERROR: Couldn't add manifest to executable '%'\n", exe_path);
        }
    } else #if OS == .MACOS {
        if !optimized return; // When debugging, use the Unix program directly. This saves us compile time.

        // Set up our temporary directory to turn into a .dmg disk image
        DMG_DIR :: "dmg";
        run_command("mkdir", DMG_DIR);

        // Generate Focus.app inside our temporary directory
        set_working_directory(DMG_DIR);
        create_app_bundle("Focus", tprint("../build_release/%", options.output_executable_name), "../images/mac.png", "", true, true);
        write_entire_file("Focus.app/Contents/Info.plist", tprint(INFO_PLIST_CONTENTS, VERSION, VERSION));
        set_working_directory(#filepath);

        // Create a symbolic link to /Applications (what all the cool kids do)
        run_command("ln", "-s", "/Applications", DMG_DIR);

        // Generate a .DMG using Disk Utility
        run_command("hdiutil", "create", "-volname", tprint("Focus %", VERSION), "-srcfolder", DMG_DIR, "-ov", "-format", "UDZO", tprint("Focus-%-Intel.dmg", VERSION));

        // Remove our temporary directory when we're done
        run_command("rm", "-r", DMG_DIR);

        #import "MacOS_Bundler";
        #import "Process";
    }
}

has_note :: (header: *Code_Procedure_Header, note: string) -> bool {
    for header.notes  if it.text == note  return true;
    return false;
}

logger :: (message: string, data: *void, info: Log_Info) {
    if info.common_flags & .ERROR || !begins_with(message, "[Iprof]")
        context.default_logger(message, data, info);
}

#import "Compiler";
#import "Basic";
#import,file "modules/Iprof/module.jai";
#import "Metaprogram_Plugins";
#import "String";
#import "File";

#if OS == .WINDOWS {
    #import "Ico_File";
    #import "Windows_Resources";
} else #if OS == .MACOS {
    INFO_PLIST_CONTENTS :: #string STRING
<?xml version="1.0" ?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist>
    <dict>
        <key>CFBundleDevelopmentRegion</key>
        <string>en-US</string>

        <key>CFBundleDisplayName</key>
        <string>Focus</string>

        <key>CFBundleExecutable</key>
        <string>Focus</string>

        <key>CFBundleIconFile</key>
        <string>icon_data.icns</string>

        <key>CFBundleIdentifier</key>
        <string>dev.focus-editor</string>

        <key>CFBundleInfoDictionaryVersion</key>
        <string>6.0</string>

        <key>CFBundleName</key>
        <string>Focus</string>

        <key>CFBundlePackageType</key>
        <string>APPL</string>

        <key>CFBundleShortVersionString</key>
        <string>%</string>

        <key>CFBundleVersion</key>
        <string>%</string>

        <key>NSHumanReadableCopyright</key>
        <string>© 2023 Ivan Ivanov</string>
    </dict>
</plist>
STRING
}
