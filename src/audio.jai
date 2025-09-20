sfx: enum {
    NONE;
    TICK;
    COMPILING;
    COMPILE_SUCCESS;
    COMPILE_FAIL;
    BUILD_SUCCESS;
    BUILD_WARNING;
    BUILD_FAIL;
    DEBUG_RUN;
    DEBUG_HALT;
}

build_complete_sfx: type_of(sfx);

init_audio :: () {
    success := Sound.sound_player_init(.{audible_when_window_is_not_in_focus=true});
    if !success {
        add_user_message_error("Failed to init sound system.");
        return;
    }

    load_sfx(.TICK, "click.wav");
    load_sfx(.COMPILING, "zx.wav");
    load_sfx(.COMPILE_SUCCESS, "smb_kick.wav");
    load_sfx(.COMPILE_FAIL, "rodland-hit.wav");
    load_sfx(.BUILD_SUCCESS, "rodland-joy.wav");
    load_sfx(.BUILD_FAIL, "rodland-hit.wav");
    //load_sfx(.BUILD_WARNING, "");
    //load_sfx(.DEBUG_RUN, "");
    //load_sfx(.DEBUG_HALT, "");
}

update_audio :: () {
    //if last_played_build_tick {
    //    tick_interval := (cast(Time) config.settings.build_audio_tick_interval_ms) / 1000.0;
    //    if !build_task_is_running_and_started_at { // build finished
    //        Sound.stop_stream_abruptly(sound_stream_ids[sfx.TICK]);
    //        play_sfx(build_complete_sfx);
    //        last_played_build_tick = 0;
    //    }
    //    else if frame_time - last_played_build_tick >= tick_interval {
    //        play_sfx(.TICK, rate=1.22, volume=0.5);
    //        last_played_build_tick += tick_interval;
    //    }
    //}
    //else if build_task_is_running_and_started_at {
    //    last_played_build_tick = build_task_is_running_and_started_at;
    //}

    if playing_compiling {
        if !build_task_is_running_and_started_at {
            Sound.stop_stream_abruptly(sound_stream_ids[sfx.TICK]);
            playing_compiling = false;
            if build_complete_sfx == .BUILD_SUCCESS
                play_sfx(build_complete_sfx, rate=1.8);
            else
                play_sfx(build_complete_sfx);
        }
    }
    else if build_task_is_running_and_started_at {
        stream := play_sfx(.COMPILING, volume=config.settings.audio_building_volume);
        Sound.set_repeating(stream, true);
        assert(stream.repeat_end_position > 0);
        stream.play_cursor = cast(float) random_int(stream.repeat_end_position);
        playing_compiling = true;
    }

    Sound.update();
}

load_sfx :: (id: type_of(sfx), filename: string) {
    sound_data[id] = Sound.load_audio_file(tprint("%/media/%", data_dir, filename));
    if !sound_data[id].loaded
        add_user_message_error(tprint("Failed to load audio file media/%", filename));
}

play_sfx :: (id: type_of(sfx), rate := 1.0, volume := -1.0, perturb := false) -> *Sound.Sound_Stream, s64 {
    if !id  return null, -1;
    stream, stream_id := play_sfx(*sound_data[id], rate, volume, perturb);
    sound_stream_ids[id] = stream_id;
    sound_streams[id] = stream;
    return stream, stream_id;
}

play_sfx :: (data: *Sound.Sound_Data, rate := 1.0, volume := -1.0, perturb := false) -> *Sound.Sound_Stream, s64 {
    category :: Sound.Sound_Category.GENERAL_SFX;
    stream := Sound.make_stream(data, category);

    stream.user_volume_scale = ifx volume >= 0 else config.settings.audio_volume;
    stream.rate_scale = rate;

    if perturb {
        stream.user_volume_scale += random_get_within_range(-0.5, +0.4);
        stream.rate_scale        += random_get_within_range(-0.3, +0.22);
    }

    Sound.start_playing(stream);

    return stream, stream.entity_id;
}

#scope_file

sound_data: [#run enum_highest_value(type_of(sfx)) + 1] Sound.Sound_Data;
sound_stream_ids: [#run enum_highest_value(type_of(sfx)) + 1] s64;
sound_streams: [#run enum_highest_value(type_of(sfx)) + 1] *Sound.Sound_Stream;

last_played_build_tick: Time;
playing_compiling := false;
