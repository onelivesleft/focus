//
// Adapted from Sean Barrett's IProf, which I guess was
// at least a little bit adapted from my Game Developer article.
//

// @Simplify: We could just use modules/Hash_Table instead of
// doing our own zone_hash situation here.

#module_parameters(IMPORT_MODE := Import_Mode.METAPROGRAM, MANUAL_MODE := false, USE_GRAPHICS := true, DO_HISTORY := true) {
    Import_Mode :: enum u8 {
        METAPROGRAM :: 0;
        CLIENT      :: 1;
    }
};

#if IMPORT_MODE == .METAPROGRAM {
    // When being imported by a metaprogram, we provide code for instrumenting the target program,
    // including the Metaprogram_Plugin interface.

    #load "instrument.jai";
    #load "options.jai";
} else {
    // When imported by the client, we provide the actual profiling code,
    // and code for reporting the profile results (either batch-wise
    // or interactively). This is the bulk of the actual code in this module.

    #load "runtime.jai";
    #load "reports.jai";
}
