
// To Do:

// Put usage code here!

// hash the strings at compile time so we don't need id().


MAX_DEPTH :: 100;

MAX_HASH_SIZE  :: 65536;   // not unlimited, to catch unbalanced BEGIN/END_PROF.  Umm, is this no longer a concern now that instrumenting is manual? -jblow
INIT_HASH_SIZE :: 256;     // balance resource usage and avoid initial growth... MUST BE A POWER OF TWO.

zone_hash: [..] *Zone_Profiling_Data;

zone_hash_count: s64 = 0;  // Is this necessary or does it just track zone_hash.count?
zone_hash_mask:  u64 = 0;

// @abner originally file-scoped, but I see Iprof_GL.jai needing these
displayed_quantity := Report_Mode.SELF_TIME;
history_index      : s64;
display_frame      : s64;
update_cursor      := false;



#if MANUAL_MODE {
    zones: [MAX_PROFILING_ZONES] Zone;  // @Cleanup: We should compute the actual number statically, probably.
} else {
    zones: [] Zone; // Allocated in _init_zone_names()
}

// caches is a hash table that gets dynamically sized. If we could prevent doing this at startup,
// we would reduce our footprint of toxic-at-startup routines.
caches : [] *Zone_Profiling_Data; // Allocated in _init_zone_names()

#if DO_HISTORY {
    Zone_History :: struct {
        values: [NUM_FRAME_SLOTS] float32;
    }
}


#scope_module
expanded_zone:       *Zone;
zone_selected:     *Zone;

#scope_export

Zone :: struct {
    name: string;
    hash: u64;     // Hash of the name, computed at compile time.

    filename: string;
    full_path: string;
    line:     s64;

    highlevel:    *Report_Row;

    #if DO_HISTORY {
        history_self: Zone_History;
        history_hier: Zone_History;
        history_calls: Zone_History;
    }

    visited := false;
    initted := false;
}

Zone_Profiling_Data :: struct {
    t_self_start:     s64;
    total_self_ticks: s64;
    total_hier_ticks: s64;

    total_entry_count: u32;

    parent: *Zone_Profiling_Data;
    zone:   *Zone;
    recursion_depth:   s32;
    profile_tracker_data_record:         *Profile_Tracker_Data_Record;
}


stack:  *Zone_Profiling_Data; // current Zone stack
dummy:   Zone_Profiling_Data; // parent never matches
dummy2:  Zone_Profiling_Data; // parent never matches

zone_begin :: inline (zone_index: s64) #expand {
    if !zones.count return; // Happens if we instrument a procedure that is then called at compile-time before we could init Iprof!
    z := *zones[zone_index];
    cache := caches[zone_index];

    if cache.parent != stack {  // @Thread
        cache = Stack_Push(z);
        caches[zone_index] = cache;
    }

    cache.total_entry_count += 1;
    ticks := cast,no_check(s64) rdtsc();

    // Stop the timer on the parent zone stack.
    stack.total_self_ticks += ticks - stack.t_self_start;

    // Make cached stack current.
    stack = cache;

    // Start the timer on this stack.
    stack.t_self_start = ticks;
}

zone_end :: inline () {
    if !stack return;  // In case we bailed at the beginning of zone_begin.

    ticks := cast(s64) rdtsc();

    // Stop timer for current zone stack.
    stack.total_self_ticks += ticks - stack.t_self_start;

    // Make parent chain current.
    stack = stack.parent;

    // Start timer for parent zone stack.
    stack.t_self_start = ticks;
}


NUM_VALUES :: 4;
NUM_TITLE  :: 2;
NUM_HEADER :: NUM_VALUES+1;

Report_Row :: struct {
    indent:     s64;
    name:       string;
    number:     s64;
    prefix:     u8;
    value_flag: s64;

    self_time:  float64;
    hier_time:  float64;
    calls:      float64;

    #place self_time;
    array_aliased_values: [3] float64 = ---;  // Alias self_time, hier_time, calls into an array that we can use for sorting and so forth.

    heat:       float64;

    // used internally
    zone: *Zone;
}

Report :: struct {
    title:         string;
    title_right:   string;

    header:  [NUM_HEADER] string;

    hilit_header: s32 = 0;

    records: [..] Report_Row;
    hilight: s64;
}

// "High-level" stuff:

Report_Mode :: enum u8 {
    SELF_TIME;
    HIERARCHICAL_TIME;
    CALL_COUNT;

    CALL_GRAPH;
}

// number of frames of history to keep
NUM_FRAME_SLOTS :: 128;

// number of unique zones allowed in the entire application
// @Incomplete: This is now figured out at build time! Use that.
MAX_PROFILING_ZONES :: 2048;

////////////////////////////////////////////////////////////////////////

// the number of moving averages
NUM_SMOOTHING_SLOTS :: 3;

// the number of frames to ignore before starting the moving averages
NUM_THROWAWAY_UPDATES :: 3;

// threshhold for a moving average of an integer to be at zero
INT_ZERO_THRESHHOLD :: 0.25;

Prof_init_highlevel :: () {
    update_index = 0;
    last_update_time = 0;

    times_to_reach_90_percent[0] = 0.1;
    times_to_reach_90_percent[1] = 0.8;
    times_to_reach_90_percent[2] = 2.5;

    clear(*frame_time);

    for 0..NUM_SMOOTHING_SLOTS-1 {
        frame_time.values[it] = FRAME_TIME_INITIAL;
    }
}

set_report_mode :: (desired: Report_Mode) {
    displayed_quantity = desired;
}

update :: (record_data: bool) {
    timestamps_per_second: float64;

    assert(zones.count <= MAX_PROFILING_ZONES, "zones.count = %, MAX = %", zones.count, MAX_PROFILING_ZONES);

    traverse(propagate_stack);

    // Precompute the time factors

    now := get_time();
    dt: float64;

    if update_index == 0 {
        dt = FRAME_TIME_INITIAL;
    } else {
        dt = now - last_update_time;
        if dt == 0 dt = FRAME_TIME_INITIAL;
    }

    last_update_time = now;

    for * p, i: precomputed_factors {
        <<p = pow(0.1, dt / times_to_reach_90_percent[i]);
    }

    precomputed_factors[0] = 0; // instantaneous.

    current_integer_timestamp := cast(s64) rdtsc();

    timestamp_delta: s64;
    if update_index == 0 {
        prof_sum = 0;
        traverse(sum_times);
        if prof_sum == 0 prof_sum = 1;
        timestamp_delta = prof_sum;
    } else {
        timestamp_delta = current_integer_timestamp - last_integer_timestamp;
        if timestamp_delta == 0  timestamp_delta = 1;
    }

    last_integer_timestamp = current_integer_timestamp;
    timestamps_per_second = cast(float64) timestamp_delta / dt;

    if update_index < NUM_THROWAWAY_UPDATES {
        eternity_set(*integer_timestamps_per_second, timestamps_per_second);
    } else {
        update(*integer_timestamps_per_second, timestamps_per_second, precomputed_factors);
    }

    {
        ss_slot :: 1;

        ss_val := integer_timestamps_per_second.values[ss_slot];
        ss_variance := integer_timestamps_per_second.variances[ss_slot] - ss_val*ss_val;
        ss_stdev := sqrt(abs(ss_variance));

        ss_ratio: float64;
        if ss_val {
            ss_ratio = ss_stdev / abs(ss_val);
        }

        speedstep_warning = (ss_ratio > SPEEDSTEP_DETECTION_RATIO);
   }

    if timestamps_per_second {
        timestamps_to_seconds = 1.0 / timestamps_per_second;
    } else {
        timestamps_to_seconds = 0;
    }

    defer traverse(clear_stack);

    if !record_data {
        return;
    }

    #if DO_HISTORY {
        for * zones {
            it.history_self.values[history_index] = 0;
            it.history_hier.values[history_index] = 0;
            it.history_calls.values[history_index] = 0;
        }

        traverse(update_history);
    }

    update(*frame_time, dt, precomputed_factors);
    update_index += 1;

    #if DO_HISTORY {
        history_index = (history_index + 1) % NUM_FRAME_SLOTS;
    }
}

create_report :: () -> *Report {
    s: s64 = 1;
    if displayed_quantity == .CALL_GRAPH  s = 3;

    num_records := zones.count * s;

    report := New(Report, allocator=__temporary_allocator);
    report.records.allocator = __temporary_allocator;

    array_resize(*report.records, num_records, true);

    for * z, i : zones {
        r := *report.records[i*s];
        z.highlevel = r;

        if displayed_quantity == .CALL_GRAPH {
            r[0].name = z.name;
            r[1].name = z.name;
            r[2].name = z.name;
            r[0].value_flag = 1 | 2 | 4;
            r[1].value_flag = 1 | 2 | 4;
            r[2].value_flag = 1 | 2 | 4;
            r[0].indent = 3;
            r[1].indent = 5;
            r[2].indent = 0;
            r[0].zone = z;
            r[1].zone = z;
            r[2].zone = z;
            r[0].prefix = 0;
            r[1].prefix = 0;
            r[2].prefix = 0;
        } else {
            r.value_flag = 1 | 2 | 4;
            r.name = z.name;
            r.zone = z;
            r.indent = 0;
            r.prefix = 0;
        }
    }

    avg_frame_time := frame_time.values[slot];
    if avg_frame_time == 0 avg_frame_time = 0.01;

    fps := 1 / avg_frame_time;

    report.title = tprint("% ms/frame (fps: %)  ",
                          formatFloat(avg_frame_time * 1000, 3, trailing_width=3),  // @Incomplete: Also 3 in front
                          formatFloat(fps, 2, trailing_width=3)); // @Incomplete: Also 3 in front

    if display_frame {  // @Inefficient
        suffix := "";
        if display_frame > 1 suffix = "s";
        report.title_right = tprint("% frame% ago",
                                    display_frame, suffix);
    } else {
        report.title_right = "current frame";
    }

    if displayed_quantity == .CALL_GRAPH {
        r := expanded_zone.highlevel;

        traverse(propagate_expanded);
        r[2].prefix = #char "-";

        // Compact the records in-place, eliminating anything with 0 calls.
        // We could just have report_expand_compare sort these to the bottom,
        // then notice the first one that is 0, instead...
        j : s64 = 0;
        for report.records {
            if it.calls {
                report.records[j] = it;
                j += 1;
            }
        }

        report.records.count = j;

        quick_sort(report.records, report_expand_compare);

        for * report.records
            if it.indent == 5
                it.indent = 3;
    } else {
        traverse(propagate_to_zone);

        heat_index := 0;
        compare := #bake_arguments report_compare_slot(slot = 0);

        if displayed_quantity == .HIERARCHICAL_TIME {
            compare = #bake_arguments report_compare_slot(slot = 1);
            heat_index = 1;
        } else if displayed_quantity == .CALL_COUNT {
            compare = #bake_arguments report_compare_slot(slot = 2);
            heat_index = 2;
        }

        for * report.records
            it.heat = compute_heat(it.heat, it.array_aliased_values[heat_index]);

        quick_sort(report.records, compare);
    }

    if update_cursor {
        for * report.records {
            if it.zone == expanded_zone {
                cursor = it_index;
                break;
            }
        }

        update_cursor = false;
    }

    if cursor >= 0 {
        if cursor < report.records.count {
            zone_selected = report.records[cursor].zone;
        }
    }

    // Let's not set header[0] because it is kind of redundant.

    // report.header[0] = "zone";
    report.header[1] = "self";
    report.header[2] = "hier";
    report.header[3] = "count";

    if displayed_quantity == .SELF_TIME {
        report.hilit_header = 1;
    } else if displayed_quantity == .HIERARCHICAL_TIME {
        report.hilit_header = 2;
    } else if displayed_quantity == .CALL_COUNT {
        report.hilit_header = 3;
    }

    if report.records {
        Clamp(*cursor, 0, report.records.count-1);
        report.hilight = cursor;
    }

    return report;
}

#add_context already_inside_profiler_runtime := true; // This defaults to true, so that we can call things that may call guarded routines while we are starting up (for example when initting mutexes/calling threads). We set it to false at the end of init.

// This code is structured to minimize computation
// assuming there's a hit in the very first slot.
Stack_Push :: (zone: *Zone) -> *Zone_Profiling_Data {
    h := hash(zone, stack);
    x := h & zone_hash_mask;
    z := zone_hash[x];

    if (z.parent == stack) && (z.zone == zone) return z;

    // Anywhere below here, we may invoke routines from modules/Basic,
    // like alloc, etc. So, set this variable so we can safeguard against it.
    // In the normal 'fast path' case we just returned above, so most of the time
    // we are hopefully not doing this.

    context.already_inside_profiler_runtime = true;
    defer context.already_inside_profiler_runtime = false;

    if z != *dummy #no_aoc {
        // Compute a secondary hash function; force it to be odd
        // so it's relatively prime to the power-of-two table size.
        s := ((h << 4) + (h >> 4)) | 1;
        while true {
            x = (x + s) & zone_hash_mask;
            z = zone_hash[x];
            if (z.parent == stack) && (z.zone == zone) return z;
            if z == *dummy break;
        }

        // loop is guaranteed to terminate because the hash table is never full
    }

    // check if we need to grow the table
    // we keep it at most 1/2 full to be very fast
    if zone_hash_count*2 > zone_hash.allocated {
        old_hash := zone_hash;
        init_zone_hash(zone_hash.allocated*2);

        for old_hash {
            if it != *dummy insert_node(it);
        }

        z := createStackNode(zone, stack);
        insert_node(z);

        free(old_hash.data, allocator=zone_hash.allocator);

        return z;
    }

    // insert new entry in hash table
    zone_hash_count += 1;
    result := createStackNode(zone, stack);
    zone_hash[x] = result;

    return result;
}

traverse :: (func: (z: *Zone_Profiling_Data)) {
    for zone_hash
        if it != *dummy func(it);
}

move_cursor :: (num: s64) {
   cursor += num;
}

set_cursor :: (num: s64) {
   cursor = num;
}

select :: () {
    b := create_report();

    if b.hilight < b.records.count {
        z := b.records[b.hilight].zone;

        if z {
            expanded_zone = z;
            displayed_quantity = .CALL_GRAPH;
        }
    }

    update_cursor = true;
}

select_parent :: () {
    old := expanded_zone;
    b := create_report();

    for b.records {
        if it.indent == 0 break;
        if it.zone == old continue;

        expanded_zone = cast(*Zone) it.zone;
    }

    update_cursor = true;
}

set_frame :: (num: s64) {
    Clamp(*num, 0, NUM_FRAME_SLOTS-1);
    display_frame = num;
}

move_frame :: (delta: s64) {
    // convert so negative delta = "into the past"
    set_frame(display_frame - delta);
}

set_smoothing :: (x: s64) {
    Clamp(*x, 0, NUM_SMOOTHING_SLOTS-1);
    slot = x;
}

init_runtime :: () {
    runtime_allocator      = context.allocator;

    init(*stack_node_pool_mutex);
    set_allocators(*stack_node_pool, context.allocator);

    #if !MANUAL_MODE {
        zones = NewArray(AUTO_INSTRUMENT_ZONE_COUNT, Zone);
    }
    caches = NewArray(zones.count, *Zone_Profiling_Data);

    /*
    We can't dynamically initialize zones, because that calls a bunch of stuff in Basic,
    which might be instrumented, which is bad if the zones array doesn't point at memory yet.

    #if MANUAL_MODE {
        // @Incomplete:
        // We actually should be able to know at compile-time
        // how many zones there are.
        array_resize(*zones, MAX_PROFILING_ZONES);
    } else {
        array_resize(*zones, AUTO_INSTRUMENT_ZONE_COUNT);
    }

    array_resize(*caches, zones.count);
    */

    for * caches { <<it = *dummy; }

    //
    // Init the zone hash and related stuff.
    //

    stack = *dummy2;

    ZONE_GLOBAL :: 0;
    global := *zones[ZONE_GLOBAL];
    global.name = "(global)";
    expanded_zone = global;

    // @Incomplete: Need a whole separate zone array per thread! (Do we?)
    zone_hash.allocator      = context.allocator;

    init_zone_hash(INIT_HASH_SIZE);
    Prof_init_highlevel();

    context.already_inside_profiler_runtime = false;

    // Intentionally unbalanced profiling; this wraps everything else.
    {
        caches[ZONE_GLOBAL] = *dummy;
        zone_begin(ZONE_GLOBAL);
    }
}

hash :: (z: *Zone, s: *Zone_Profiling_Data) -> u64 { // @Ugh: Make a hash that is not based on pointer values?
    return cast(u64) z.hash + cast(u64) s;   // We want s.zone.hash but I guess sometimes s.zone is null!
}

insert_node :: (q: *Zone_Profiling_Data) #no_aoc {
    h := hash(q.zone, q.parent);
    x := h & zone_hash_mask;
    s := ((h << 4) + (h >> 4)) | 1;

    while zone_hash[x] != *dummy
        x = (x + s) & zone_hash_mask;

    zone_hash[x] = q;

    zone_hash_count += 1;
}

count_recursion_depth :: (stack: *Zone_Profiling_Data, zone: *Zone) -> s32 {
    n: s32;

    while stack {
        if stack.zone == zone  n += 1;
        stack = stack.parent;
    }

    return n;
}

createStackNode :: (zone: *Zone, parent: *Zone_Profiling_Data) -> *Zone_Profiling_Data {
    z: *Zone_Profiling_Data = ---;
    {
        lock(*stack_node_pool_mutex);
        allocator: Allocator;
        allocator.proc = pool_allocator_proc;
        allocator.data = *stack_node_pool;
        z = New(Zone_Profiling_Data, allocator=allocator);
        unlock(*stack_node_pool_mutex);
    }

    z.zone = zone;
    z.parent = parent;
    z.recursion_depth = count_recursion_depth(parent, zone);

    return z;
}


init_zone_hash :: (size: s64) {
    assert(size <= MAX_HASH_SIZE);
    zone_hash_count = 0;
    zone_hash_mask  = cast (u64) size-1;

    // @Ugly:
    // Instead of using array_reserve, just alloc the data,
    // because Stack_Push relies on this routine
    // giving us back an array with memory different from the
    // old array's memory.
    // @Cleanup:
    // Rewrite the caller so we don't need this!

    zone_hash.data = alloc(size_of(*Zone_Profiling_Data) * size, zone_hash.allocator);
    zone_hash.allocated = size;
    zone_hash.count = size;

    for 0..size-1
        zone_hash[it] = *dummy;
}

// these structures are used solely to track data over time
History_Scalar :: struct {
    values:    [NUM_SMOOTHING_SLOTS] float64;
    variances: [NUM_SMOOTHING_SLOTS] float64;

    history:    [NUM_FRAME_SLOTS] float;  // Needed only if Prof_CALL_HISTORY but we don't have #ifdef yet.
}

Profile_Tracker_Data_Record :: struct {
    self_time: History_Scalar;
    hierarchical_time: History_Scalar;
    entry_count: History_Scalar;
    max_recursion: s64;
}

frame_time: History_Scalar;

times_to_reach_90_percent: [NUM_SMOOTHING_SLOTS] float64;
precomputed_factors      : [NUM_SMOOTHING_SLOTS] float64;

num_active_zones: s64;
update_index:     s64;
last_update_time: float64;

FRAME_TIME_INITIAL :: 0.001;

slot:          s64 = 1;

clear :: (using s: *History_Scalar) {
    for i : 0..NUM_SMOOTHING_SLOTS-1 {
        values[i] = 0;
        variances[i] = 0;
    }
}

update :: (using s: *History_Scalar, new_value: float64, k_array: [] float64) {
   new_variance := new_value * new_value;

    for i : 0..NUM_SMOOTHING_SLOTS-1 {
        k := k_array[i];
        values[i] = values[i] * k + new_value * (1 - k);
        variances[i] = variances[i] * k + new_variance * (1 - k);
    }

//#ifdef Prof_CALL_HISTORY
    history[history_index] = cast(float) new_value;
//#endif
}

eternity_set :: (using s: *History_Scalar, new_value: float64) {
    new_variance := new_value * new_value;

    for i : 0..NUM_SMOOTHING_SLOTS-1 {
        values[i] = new_value;
        variances[i] = new_variance;
    }
// #ifdef Prof_CALL_HISTORY
   history[history_index] = cast(float) new_value;
//#endif
}

get_value :: (using s: *History_Scalar) -> float64 {
//#ifdef Prof_CALL_HISTORY
   if display_frame
      return history[(history_index - display_frame + NUM_FRAME_SLOTS) % NUM_FRAME_SLOTS];
//#endif
   return values[slot];
}

propagate_stack :: (c: *Zone_Profiling_Data) {
    p := c;

    // Propagate times up the stack for hierarchical
    // times, but watch out for recursion.

    while p.zone {
        if !p.zone.visited {
            p.total_hier_ticks += c.total_self_ticks;
            p.zone.visited = true;
        }

        p = p.parent;
    }

    p = c;
    while p.zone {
        p.zone.visited = false;
        p = p.parent;
    }
}

clear_stack :: (using c: *Zone_Profiling_Data) {
    total_hier_ticks = 0;
    total_self_ticks = 0;
    total_entry_count = 0;
}

prof_sum: s64;  // @Hack @Cleanup if we have closures or something? Use a client data pointer?
sum_times :: (c: *Zone_Profiling_Data) {
    prof_sum += c.total_self_ticks;
}

timestamps_to_seconds: float64;

update_history :: (c: *Zone_Profiling_Data) {
    record := c.profile_tracker_data_record;
    z := c.zone;

    if record == null {
        record = New(Profile_Tracker_Data_Record, allocator=runtime_allocator);
        c.profile_tracker_data_record = record;
    }

    if c.recursion_depth > record.max_recursion
        record.max_recursion = c.recursion_depth;

    self_time   := c.total_self_ticks * timestamps_to_seconds;
    hier_time   := c.total_hier_ticks * timestamps_to_seconds;
    entry_count := c.total_entry_count;

    if update_index < NUM_THROWAWAY_UPDATES {
        eternity_set(*record.entry_count,       cast(float64) entry_count);
        eternity_set(*record.self_time,         self_time);
        eternity_set(*record.hierarchical_time, hier_time);
    } else {
        update(*record.self_time,         self_time,   precomputed_factors);
        update(*record.hierarchical_time, hier_time,   precomputed_factors);
        update(*record.entry_count,       cast(float64) entry_count, precomputed_factors);
    }

    if DO_HISTORY {
        z.history_self.values[history_index] += cast(float) self_time;
        z.history_hier.values[history_index] += cast(float) hier_time;
        z.history_calls.values[history_index] += cast(float) entry_count;
    }
}

SPEEDSTEP_DETECTION_RATIO : float64 : 0.08;
speedstep_warning: bool;

// @Cleanup: These were static locals to Prof_update in the C version.
// But when we support multithreading they will need to be in a struct anyway.
integer_timestamps_per_second: History_Scalar;
last_integer_timestamp:    s64;

propagate_to_zone :: (c: *Zone_Profiling_Data) {
    r := c.zone.highlevel;
    d := c.profile_tracker_data_record;

    if d {
        r.self_time += 1000 * get_value(*d.self_time);
        r.hier_time += 1000 * get_value(*d.hierarchical_time);
        r.calls     +=        get_value(*d.entry_count);

        // arbitrary determination for how low a moving average
        // has to go to reach 0
        if get_value(*d.entry_count) > INT_ZERO_THRESHHOLD {
            if d.max_recursion > r.number
                r.number = d.max_recursion;
            if c.parent.zone {
                c.parent.zone.highlevel.prefix = #char "+";
            }
        }

        //#ifdef Prof_CALL_HISTORY
        if display_frame return;  // no variances when examining history
        //#endif

        t: float64;
        if displayed_quantity == .HIERARCHICAL_TIME {
            t = d.hierarchical_time.variances[slot];
        } else {
            t = d.self_time.variances[slot];
        }

        t = 1000 * 1000 * t;

        if r.heat == 0
            r.heat = t;
        else
            r.heat = r.heat + t + 2 * sqrt(r.heat * t);
    }
}

propagate_expanded :: (c: *Zone_Profiling_Data) {
    d := c.profile_tracker_data_record;
    if d == null return;

    if c.parent.zone && (get_value(*d.entry_count) > INT_ZERO_THRESHHOLD) {
        rec := c.parent.zone.highlevel;
        rec[0].prefix = #char "+";
        rec[1].prefix = #char "+";
        rec[2].prefix = #char "+";
    }

    if c.zone == expanded_zone {
        r := expanded_zone.highlevel;
        // accumulate this time to ourselves
        r[2].self_time += 1000 * get_value(*d.self_time);
        r[2].hier_time += 1000 * get_value(*d.hierarchical_time);
        r[2].calls     +=        get_value(*d.entry_count);

        if (d.max_recursion > r[2].number) && (get_value(*d.entry_count) > INT_ZERO_THRESHHOLD)
            r[2].number = d.max_recursion;

        // propagate it to the parents
        if c.parent.zone {
            r = c.parent.zone.highlevel;
            r[1].self_time += 1000 * get_value(*d.self_time);
            r[1].hier_time += 1000 * get_value(*d.hierarchical_time);
            r[1].calls     +=        get_value(*d.entry_count);

            d = c.parent.profile_tracker_data_record;
            if (d.max_recursion > r[1].number) && (get_value(*d.entry_count) > INT_ZERO_THRESHHOLD)
                r[1].number = d.max_recursion;
        }
    }

    if c.parent.zone == expanded_zone {
        r := c.zone.highlevel;
        r[0].self_time += 1000 * get_value(*d.self_time);
        r[0].hier_time += 1000 * get_value(*d.hierarchical_time);
        r[0].calls     +=        get_value(*d.entry_count);

        if (d.max_recursion > r[0].number && get_value(*d.entry_count) > INT_ZERO_THRESHHOLD)
            r[0].number = d.max_recursion;
    }
}

compute_heat :: (variance: float64, value: float64) -> float64 {
    VARIANCE_TOLERANCE_FACTOR :: 0.5;

    fabs_value := abs(value);

    variance -= value*value;
    if variance < 0 variance = 0;

    stdev := sqrt(variance);

    factor: float64;

    if fabs_value < 0.000001 {
        return 0;
    } else {
        factor = (stdev / fabs_value) * (1.0 / VARIANCE_TOLERANCE_FACTOR);
    }

    Clamp(*factor, 0, 1);
    return factor;
}

report_compare_slot :: (p: Report_Row, q: Report_Row, slot: s64) -> s64 {
    a := p.array_aliased_values[slot];
    b := q.array_aliased_values[slot];

    EPSILON :: 0.001;
    if b < a - EPSILON return -1;
    if b > a + EPSILON return  1;

    delta := p.name.count - q.name.count;
    if delta != 0 return delta;

    return compare_strings(p.name, q.name);  // Prevent oscillation when values are equal.
}

report_expand_compare :: (a: Report_Row, b: Report_Row) -> s64 {
    if a.indent != b.indent {
        if a.indent == 5 return -1;
        if b.indent == 5 return 1;
        if a.indent == 3 return 1;
        if b.indent == 3 return -1;
        return 0;
    }

    if a.hier_time == b.hier_time  return 0;

    if a.hier_time < b.hier_time {
        if a.indent == 5 return -1;
        return 1;
    }

    if a.indent == 5 return 1;
    return -1;
}

GraphLocation :: struct {
    x0, y0: float;
    sx, sy: float;
}

cursor: s64;

#scope_export

// Automatic_Zone is called by auto-instrumented code.
// In principle we would like Automatic_Zone to be cheap
// and not contain an 'if' statmement. But unfortunately
// we have to use Automatic_Zone_Guarded always right now,
// because otherwise if a program has a #run directive that
// calls procedures that could also happen at runtime, well,
// they will try to do Iprof zone stuff and this is bad.
// In the long term we would like to figure this out.
// That said, when we cross-compile, then the compile-time
// versions of procedures probably have to be different from
// the runtime versions anyway, so this solution should slot
// naturally into that.
#if IMPORT_MODE==.CLIENT {
/*
    Automatic_Zone :: (index: s64) #expand {
        zone_begin(index);
        `defer zone_end();
    }
*/
    Automatic_Zone :: Automatic_Zone_Guarded; // :AutomaticZoneAlwaysGuarded
} else {
    Automatic_Zone :: (index: s64) #expand {}
}

// We use Automatic_Zone_Guarded inside stuff like modules/Basic,
// which we might invoke from Iprof's own code, but don't want
// to cause a horrible recursion explosion. It's slower than
// Automatic_Zone() due to the 'if' statements.
Automatic_Zone_Guarded :: (index: s64) #expand {
    already := context.already_inside_profiler_runtime;

    if !already zone_begin(index);
    `defer if !already zone_end();
}


//#placeholder _init_zone_names;

Prepend_To_Main :: () #expand {
    init_runtime();

    // Backtick on init_zone_names because it is injected into the main program right now. (We don't necessarily have a way to inject it into Iprof cleanly at this time...)
    `_init_zone_names();

    log("%", "Starting Profiling.\n");
    update(true);  // Since this is a frame-based profiler, we call update() for the first time to start things off.

    `defer {
        // @Incomplete: Do a better job.
        update(true);

        report := create_report();
        log_text_report(report);

        if CSV_OUTPUT_FILENAME {
            name := CSV_OUTPUT_FILENAME;
            log("\n");
            log("Outputting the profile to csv file '%'.\n", name);
            save_csv_report(report, name);
        }
    }
}

#scope_file

#import "Sort";
#import "Basic";
#import "Math";
#import "Pool";
#import "Thread";
#import "Machine_X64";  // For rdtsc, etc.
#import "String";

#if !MANUAL_MODE {
    #import "Compiler";
    #import "Metaprogram_Plugins";

    #scope_module
    #placeholder AUTO_INSTRUMENT_ZONE_COUNT;
    #placeholder CSV_OUTPUT_FILENAME;
}

#scope_file

#if USE_GRAPHICS {
    #load "iprof_draw.jai";
}

runtime_allocator: Allocator;

stack_node_pool: Pool;
stack_node_pool_mutex: Mutex;
