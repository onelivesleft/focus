default_message_duration : float64 : 10;
default_error_duration : float64 : -1;

user_message_allocator : Allocator;

add_user_error :: inline (message: string, duration_in_seconds := default_error_duration, icon := "", origin := User_Message.Origin.general) {
    add_user_message(message, .error, cast(Time) duration_in_seconds, icon, origin);
}

add_user_neutral :: inline (message: string, duration_in_seconds := default_message_duration, icon := "", origin := User_Message.Origin.general) {
    add_user_message(message, .neutral, cast(Time) duration_in_seconds, icon, origin);
}

add_user_warning :: inline (message: string, duration_in_seconds := default_message_duration, icon := "", origin := User_Message.Origin.general) {
    add_user_message(message, .warning, cast(Time) duration_in_seconds, icon, origin);
}

add_success_message :: inline (message: string, duration_in_seconds := default_message_duration, icon := "", origin := User_Message.Origin.general) {
    add_user_message(message, .success, cast(Time) duration_in_seconds, icon, origin);
}

add_user_message :: (message: string, level: User_Message.Level, duration_in_seconds: Time, icon := "", origin := User_Message.Origin.general) {
    if user_messages.count >= MAX_MESSAGES  return;

    user_message := User_Message.{
        state              = .arriving,
        text               = copy_string(trim(split_into_two(message, #char "\n")), user_message_allocator),
        icon               = icon,
        level              = level,
        origin             = origin,
        start_time         = cast(Time) get_time(),
        duration_in_seconds = cast(Time) duration_in_seconds,
        current_state_duration = User_Message.arrival_duration
    };

    done := false;
    if origin == .build {
        for * user_messages {
            if it.origin == .build {
                it.* = user_message;
                it.start_time = 0;
                it.state = .staying;
                it.flash_time = frame_time;
                done = true;
                break;
            }
        }
    }
    if !done  array_add(*user_messages, user_message);
}

set_user_build_message :: (result: User_Message.Level) {
    build_message_duration : Time : 5;
    for * user_messages {
        if it.origin == .build {
            it.flash_time = frame_time;
            if result == .success {
                it.start_time = frame_time;
                it.level = .success;
                it.current_state_duration = build_message_duration;
            }
            else {
                it.start_time = 0;
                it.level = result;
                it.current_state_duration = -1;
            }
            break;
        }
    }
}

update_user_messages :: () {
    // Remove dead messages
    for < user_messages {
        if it.state == .departing && frame_time >= it.start_time + it.current_state_duration {
            free(it.text, user_message_allocator);
            array_ordered_remove_by_index(*user_messages, it_index);
        }
    }

    // Check transitions
    for * user_messages  {
        if it.dismissed && it.state != .departing {
            it.state = .departing;
            it.start_time = frame_time;
            it.current_state_duration = User_Message.depart_duration;
        }
        else if it.start_time && frame_time >= it.start_time + it.current_state_duration {
            if it.state == {
                case .arriving;
                it.state = .staying;
                if it.duration_in_seconds >= 0 {
                    it.start_time = frame_time;
                    it.current_state_duration = it.duration_in_seconds;
                }
                else {
                    it.start_time = 0;
                }

                case .staying;
                it.state = .departing;
                it.start_time = frame_time;
                it.current_state_duration = User_Message.depart_duration;

                case .departing;
                // handled at top of proc, won't happen
            }
        }
    }
}

get_user_messages :: () -> [] User_Message {
    return user_messages;
}

clear_user_messages :: () {
    for user_messages free(it.text, user_message_allocator);
    array_reset_keeping_memory(*user_messages);
}

clear_user_messages :: (origin: User_Message.Origin) {
    for < user_messages {
        if it.origin == origin {
            free(it.text, user_message_allocator);
            array_ordered_remove_by_index(*user_messages, it_index);
        }
    }
}

User_Message :: struct {
    state: enum { arriving; staying; departing; };
    text: string;
    icon: string;
    level: Level;
    origin: Origin;
    start_time: Time;
    current_state_duration: Time;
    duration_in_seconds: Time;
    flash_time: Time;
    dismissed: bool;
    rect: Rect;

    Level :: enum { warning; error; success; neutral; };
    Origin :: enum { general; build; };

    arrival_duration : Time : 0.2;
    depart_duration : Time : 0.2;
    flash_duration : Time : 0.2;
}

#scope_file

user_messages: [..] User_Message;

MAX_MESSAGES    :: 64;  // need to cleanup after that
