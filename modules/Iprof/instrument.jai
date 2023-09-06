//
// This file is for instrumenting code at compile-time via a metaprogram.
// This is one of the two modes of operation supported by this compiler.
// (The other mode involves manually typing in the profiling hooks.)
//


// get_plugin() tells the metaprogram what the various hooks are:
get_plugin :: () -> *Metaprogram_Plugin {
    p := New(My_Plugin);  // We are making this on the heap so you could have more than one instance of this plugin running.

    p.before_intercept = before_intercept;
    p.add_source       = add_source;
    p.message          = message;
    p.finish           = finish;
    p.shutdown         = shutdown;

    p.log_help         = log_help;

    p.handle_one_option = handle_one_option;

    BUFFER_SIZE :: 4096;
    buffer: [BUFFER_SIZE] u8;
    s := get_working_directory();  // @Cleanup: Just make this take a [] u8.
    // Convert backslashes to forward-slashes.
    for 0..s.count-1
        if s[it] == #char "\\" { s[it] = #char "/"; }

    p.current_working_directory = copy_string(s);

    p.prepend_main_nodes = compiler_get_nodes(prepend_main);
/*
    p.prepend_general_call = cast(*Code_Procedure_Call) compiler_get_nodes(prepend_general);
    assert(p.prepend_general_call.kind == .PROCEDURE_CALL);

    p.prepend_guarded_call = cast(*Code_Procedure_Call) compiler_get_nodes(prepend_guarded);
    assert(p.prepend_guarded_call.kind == .PROCEDURE_CALL);
*/
    return p;
}

//
// Here are the hooks that get called directly at compile-time:
//
before_intercept :: (p: *Metaprogram_Plugin, flags: *Intercept_Flags) {
    my := cast(*My_Plugin) p;
}

add_source :: (p: *Metaprogram_Plugin) {
    my := cast(*My_Plugin) p;
    w := p.workspace;
    assert(w >= 0);
    add_build_string(TO_INSERT, w);
}

message :: (p: *Metaprogram_Plugin, message: *Message) {
    if injected_final_profiling_code  return;

    my := cast(*My_Plugin) p;

    if message.kind == .PHASE {
        phase_message := cast (*Message_Phase) message;
        phase := phase_message.phase;

        if phase == .TYPECHECKED_ALL_WE_CAN {
            if !injected_final_profiling_code && instrumented_entry_point {
                injected_final_profiling_code = true;

                tally := zone_infos.count;
                log("[Iprof] Adding the zone initialization code for % zones.\n", tally);

                s := tprint("AUTO_INSTRUMENT_ZONE_COUNT :: %;\n#poke_name __Iprof AUTO_INSTRUMENT_ZONE_COUNT;\nCSV_OUTPUT_FILENAME :: \"%\"; #poke_name __Iprof CSV_OUTPUT_FILENAME;\n", tally, my.csv_output_filename);
                add_build_string(s, message.workspace);

                add_hook(message.workspace, "iprof_per_frame_hook", "()", my.per_frame_hook_name, "()");
                add_hook(message.workspace, "iprof_editor_hook", "(filename: string, line: s64)", my.editor_hook_name, "(filename, line)");

                font_def := tprint("PROF_FONT_NAME :: \"%\";\n", my.font_name);
                add_build_string(font_def, message.workspace);

                builder: String_Builder;
                append(*builder, "_init_zone_names :: () {\n");
                append(*builder, "    z: *__Iprof.Zone;\n");

                for zone_infos {
                    // We hash the name so that it has a consistent ID.
                    hash := crc64(it.name);

                    // We don't have array literals yet, so we emit assignments.
                    full_path := "";
                    if it.load full_path = it.load.fully_pathed_filename;
                    print_to_builder(*builder,"    z = *__Iprof.zones[%]; z.name = \"%\"; z.hash = 0x%; z.filename = \"%\"; z.full_path = \"%\"; z.line = %;\n", it_index, it.name, formatInt(hash, base = 16), full_path, full_path, it.line); // @Incomplete: 'full_path' used also for short name for now.
                }
                append(*builder, "} @NoProfile\n");

                init_zone_names_string := builder_to_string(*builder);
                defer free(init_zone_names_string);

                // Enable this to see what we are printing.
                // print("Name initter: %\n", init_zone_names_string);
                add_build_string(init_zone_names_string, message.workspace);
            }
        }

        return;
    }

    if message.kind != .TYPECHECKED         return;

    m := cast(*Message_Typechecked) message;

    assert(!injected_final_profiling_code);
    for * tc: m.procedure_bodies {
        body := tc.expression;

        if body.body_flags & .ALREADY_MODIFIED continue;

        h := body.header;
        assert(h != null);

        if h.procedure_flags & (h.procedure_flags.POLYMORPHIC | .COMPILER_GENERATED | .COMPILE_TIME | .QUICK | .TYPE_ONLY | .MACRO) continue;  // @Incomplete: Need maybe we want a user-generated compile_time flag; that would be different than this, which is to detect #compiler.

        is_entry_point := (h.procedure_flags & .ENTRY_POINT) != 0;

        file := body.enclosing_load;
        use_guarded_macro := false;

        type := cast(*Type_Info_Procedure) h.type;
        if type.procedure_flags & .HAS_NO_CONTEXT {
            // We could use the unguarded version of Automatic_Zone here.
            // But that is currently just an alias for Automatic_Zone_Guarded, which uses the context.
            // So we can’t profile #c_call or #no_context functions atm.
            // :AutomaticZoneAlwaysGuarded
            continue;
        }

        // if h.name == "structs_as_procedure_parameters" {
        //     log("Procedure body for \"%\" (s:%) at %:% (%, %)", h.name, formatInt(h.serial, base = 16), get_filename(h), h.l0, body.body_flags, h.procedure_flags);
        //     builder: String_Builder;
        //     print_expression(*builder, h);
        //     log("It currently looks like this: %", builder_to_string(*builder));
        // }

        // Don't profile stuff that is in Iprof itself:
        // @Robustness: Hardcoded module name for now.
        if file && file.enclosing_import {
            import := file.enclosing_import;

            if import.module_name == "Iprof"  continue;
            if import.module_type == .PRELOAD continue;
            if import.module_type == .RUNTIME_SUPPORT continue;

            if import.module_type != .MAIN_PROGRAM {
                if !my.instrument_modules continue;

                if import.module_name == "Pool" {
                    continue; // Do not instrument this stuff, as runtime.jai needs to call it before we are initialized. We have our own version instead.
                }

                if import.module_name == "Thread" {
                    use_guarded_macro = true;
                }

                if import.module_name == "Basic" {
                    if h.name == "temporary_allocator_proc" continue; // This causes a circular dependency if we instrument it, as we need this for our Pool stuff. Or not??
                    if h.name == "IsScalar" continue; // Also a circular dependency here. Not sure why.

                    if contains(file.fully_pathed_filename, "module.jai") {
                        use_guarded_macro = true;
                    }
                }
            }
        }

        if !is_entry_point {  // We always need to instrument the entry point, because that is where we put the startup and shutdown.
            if tc.subexpressions.count < my.min_size continue; // Too small!
            if my.should_instrument {  // If this procedure has been given to us by the user.
                if !my.should_instrument(body) continue;
            }

            for h.notes {
                if it.text == "NoProfile" {
                    log("[Iprof] Skipping '%' due to NoProfile note.\n", h.name);
                    continue;
                }
            }
        }

        //     hook_idents(decl);  @Incomplete :GraphicalStuff

        zone_index := zone_infos.count;

        info := array_add(*zone_infos);
        info.name      = h.name;
        info.load      = h.enclosing_load;
        info.line      = h.l0;


        w := message.workspace;

        new_statements : [..] *Code_Node;
        array_reserve(*new_statements, body.block.statements.count + 2);

        if is_entry_point {
            array_add(*new_statements, my.prepend_main_nodes);
            instrumented_entry_point = true;
        }

        {
                /*
                // @Robustness: We have to copy this right now in order for the compiler not to barf.
            // This is a good opportunity to make a support library to do copy_and_insert.
            source_ident := cast(*Code_Ident)my.prepend_general_call.procedure_expression;
            ident := New(Code_Ident);  // @Speed @Leak
            <<ident = source_ident;

            source_call := my.prepend_general_call.procedure_expression;

            literal := New(Code_Literal);  // @Speed @Leak
            literal.kind = .LITERAL;
            literal.value_type = .NUMBER;
            literal.values._s64 = zone_index;
            literal.value_flags = .IS_A_NUMBER;

            array := NewArray(1, *Code_Node);  // @Speed @Leak
            array[0] = literal;

            call := New(Code_Procedure_Call);  // @Speed @Leak
            call.kind = .PROCEDURE_CALL;
            call.procedure_expression = ident;
            call.arguments_sorted = array;
            array_add(*new_statements, call);
            */

            // @Speed: VERY inefficient way to do this insofar as the compiler is concerned!
            s := ifx use_guarded_macro then tprint("context._Iprof.Automatic_Zone_Guarded(%);", zone_index)
            else                            tprint("context._Iprof.Automatic_Zone(%);", zone_index);

            literal := New(Code_Literal);  // @Speed @Leak
            literal.kind = .LITERAL;
            literal.value_type = .STRING;
            literal.values._string = s;
            insert := New(Code_Directive_Insert);  // @Speed @Heap!
            insert.kind = .DIRECTIVE_INSERT;
            insert.expression = literal;
            insert.location = body.location;       // To print the right location in added_strings

            array_add(*new_statements, insert);
        }

        for body.block.statements   array_add(*new_statements, it);

        body.block.statements = new_statements;

        // Submit the modify.
        //    print("Modifying procedure '%', zone index %.\n", proc.name, zone_index);
        //    print("Zone Declaration: %\n", << zone_decl);
        //    print("Root Expression: %\n", << cast(*Code_Literal) zone_decl.root_expression);

        compiler_modify_procedure(w, body);
    }
}

finish :: (p: *Metaprogram_Plugin) {
    my := cast(*My_Plugin) p;
}

shutdown :: (p: *Metaprogram_Plugin) {
    free(p);
}

//
// At compile-time we detect the procedures we want to profile,
// and make a procedure that creates Zones for them at startup.
// Zone_Info is a struct that we use here, only at compile-time,
// to record which Zones we want to make. At the end of compile-time
// we will output source code for these.
//




Zone_Info :: struct {
    name:      string;
    load:      *Message_File;
    line:      s64;
}

zone_infos: [..] Zone_Info;  // Zone index will be preserved into runtime.

// With TO_INSERT, we declare a global symbol that imports Iprof and then
// do an #add_context that binds to that symbol. This seems redundant, but
// if we just say #add_context :: #import "Iprof", the import won't happen
// until the context gets finalized, which then means that anything imported
// by Iprof would be unable to add any thing to the context.
//
// Why are we adding an entry to the context? It's so that submodules can see
// the import, so that the code we inject actually works.
TO_INSERT :: #string DONE
__Iprof :: #import "Iprof"(IMPORT_MODE=.CLIENT);
#add_context _Iprof :: __Iprof;
DONE

// prepend_general :: #code context._Iprof.Automatic_Zone(0);
// prepend_guarded :: #code context._Iprof.Automatic_Zone_Guarded(0);
prepend_main    :: #code context._Iprof.Prepend_To_Main();

injected_final_profiling_code := false;
instrumented_entry_point := false;

add_hook :: (w: Workspace, iprof_hook_name: string, iprof_hook_args: string, user_hook_name: string, user_hook_args: string) {
    insertion := "";
    if user_hook_name insertion = sprint("    % %;\n", user_hook_name, user_hook_args);
    defer if insertion free(insertion.data);

    body := tprint("% :: % {\n%\n}\n\n", iprof_hook_name, iprof_hook_args, insertion);

    add_build_string(body, w);
}

/* :GraphicalStuff
hook_idents :: (decl: *Code_Declaration) -> bool {
    for decl.expressions {
        if it.kind != .IDENT continue;

        ident := cast(*Code_Ident) it;
        if ident.name == "get_next_event" {
            ident.name = "iprof_get_next_event";
            return true;  // Modified!
        }

        if (ident.name == "swap_buffers") && (decl.filename != "Iprof_GL.jai") {  // We need to call swap_buffers() ourselves!!
            ident.name = "Prof_update_and_draw";
            return true;  // Modified!
        }
    }

    return false;
}
*/

#scope_module

MINIMUM_SIZE_DEFAULT :: 30;

My_Plugin :: struct {
    #as using base: Metaprogram_Plugin;

    // These can be filled out by the user after calling get_plugin():

    should_instrument: (body: *Code_Procedure_Body) -> bool;

    per_frame_hook_name: string;
    editor\  _hook_name: string;
    font_name:           string;


    //
    // These things are set by commandline options:
    //
    csv_output_filename: string;
    min_size := MINIMUM_SIZE_DEFAULT;
    instrument_modules := false;

    //
    // The user should not mess with these:
    //
    current_working_directory: string;
//    prepend_general_call: *Code_Procedure_Call;
//    prepend_guarded_call: *Code_Procedure_Call;
    prepend_main_nodes:   *Code_Node;
}

#import "Crc";
#import "Basic";
#import "Compiler";
#import "File";
#import "String";

// #import "Program_Print";
