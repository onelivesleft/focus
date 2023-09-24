eye_tracking_active :: true;
eye_tracking_hot := false;
should_jump_to_eye_tracker := -1;

calibrated_eye_position : Vector2;

#scope_file

raw_eye_position : Vector2;
calibration_offset : Vector2;

calibration_key : u32 : VK_INSERT;//124;

#load "tobii.jai";

#scope_export

gaze_position_callback :: (data: IL_GazePointData, ctx: *void) #c_call {
    ScreenToClient :: (hwnd: HWND, p: *POINT) -> s32 #foreign user32;
    push_context <<cast(*Context)ctx {
        if data.validity {
            p : POINT = ---;
            p.x = cast(s32)data.x;
            p.y = cast(s32)data.y;
            ScreenToClient(window, *p);
            raw_eye_position.x = cast(float32)p.x + 1920;
            raw_eye_position.y = screen.h - cast(float32)p.y;
            calibrated_eye_position = raw_eye_position + calibration_offset;
        }
    }
}


intlib : *IL_Context;

eye_tracking_init :: () {
    // create the interaction library
    IL_CreateInteractionLib(*intlib, .IL_FieldOfUse_Interactive);

    // assume single screen with size 2560x1440 and use full screen (not window local) coordinates
    width  :: 1920.0;
    height :: 1080.0;
    offset :: 0.0;

    IL_CoordinateTransformAddOrUpdateDisplayArea(intlib, width, height, 0, 0, 0, 0, null);
    IL_CoordinateTransformSetOriginOffset(intlib, offset, offset);

    // setup ids and rectangles that define the interactors we want to use (one in each corner of the screen),
    // then add them to the interaction library
    id : IL_InteractorId = 0;

    rect := IL_Rectangle.{0, 0, width, height};

    z :: 0.0;

    IL_BeginInteractorUpdates(intlib);

    IL_AddOrUpdateInteractor(intlib, id, rect, z);

    IL_CommitInteractorUpdates(intlib);

    IL_SubscribeGazePointData(intlib, gaze_position_callback, *context);
}


eye_tracking_tick :: () {
    eye_tracking_hot = Input.is_key_held(18) && Input.is_key_held(17);

    if eye_tracking_hot
        IL_WaitAndUpdate(intlib, 0);
    else
        IL_Update(intlib);


    if Input.is_key_held(calibration_key) {
        eye_tracking_hot = true;
        delta := mouse.pointer - raw_eye_position;
        calibration_offset = (calibration_offset + delta) * 0.5;
        //print("eye: %  mouse: %  screen: %\n", eye_position, mouse.pointer, screen);
    }

}

eye_tracking_done :: () {
    IL_DestroyInteractionLib(intlib);
}

#scope_file

user32   :: #system_library "user32";
