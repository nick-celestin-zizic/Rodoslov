window: struct {
    handle: Window_Type;
    width, height := 1600, 900;
};

DO_DTC :: !true;
#if DO_DTC {
    DTC :: #import "ncz/Dangerous_Threads_Crew";
    input_state: *DTC.Input_State;
} else {
    using Input :: #import "Input";
}

#import "Window_Creation";

Person_Row :: SQLite_Types.family.persons;
Person_Key :: type_of(SQLite_Types.family.persons.id);

family_tree: struct {
    root    :  Family_Subtree;
    depth   :  int;
    pool    :  Pool;
    dirty   :  enum { CHOOSE_ROOT; REFLOW; CLEAN; };
    root_id := -1 .(Person_Key);
}

Family_Subtree :: struct {
    using row : Person_Row;
    layout    : Family_Subtree_Layout;
    spouses   : []Person_Row;
    children  : []#this;
}

family_tree_from_sqlite :: (db: *SQLite_Context, root_id: Person_Key, current_depth := 1) -> (Family_Subtree, depth: int) {
    status :  Result;
    tree   :  Family_Subtree;
    depth  := current_depth;
    
    status, tree.row = get_person(db, root_id);
    assert(status == .OK);
    
    status, tree.spouses = get_spouses(db, root_id);
    assert(status == .OK);
    
    children: [..]Family_Subtree;
    for tree.spouses {
        status =, keys := get_children_keys(db, root_id, it.id,, temp);
        assert(status == .OK);
        next_depth := depth+1;
        for keys {
            c, d := family_tree_from_sqlite(db, it, next_depth);
            depth = max(depth, d);
            array_add(*children, c);
        }
    }
    tree.children = children;
    
    return tree, depth;
}

family_tree_to_sqlite :: (db: *SQLite_Context, using tree: Family_Subtree) {
    assert_helper("TODO");
}

family_tree_compute_layout :: (using tree: *Family_Subtree) {
    SPOUSE_GAP_UNITS   := 1.0 + SIBLING_GAP_UNITS;
    COUPLE_WIDTH_UNITS := 1.0 + SPOUSE_GAP_UNITS;  // Derived - width of a married couple

    couple_units := 1.0;
    children_group_units := 0.0;
    if spouses {
        assert(spouses.count == 1, "TODO: multiple spouses");
        couple_units = COUPLE_WIDTH_UNITS;
        spouse := spouses[0];
        
        if children {
            num_children := children.count;
            for *children {
                family_tree_compute_layout(it);
                children_group_units += it.layout.width_units;
            }
            if   num_children > 1
            then children_group_units += (num_children - 1) * SIBLING_GAP_UNITS;
        }
    }
    
    layout = {
        max(couple_units, children_group_units),
        ifx children_group_units > couple_units then 0.5 * (children_group_units - couple_units),
    };
}

family_tree_to_text :: (sb: *String_Builder, using tree: Family_Subtree, generation := 1, order := 1) {
    print_person :: (sb: *String_Builder, using person: Person_Row) {
        print_full_name(sb, person);
        print(sb, " % (%", gender, birth_year);
        if death_year print(sb, "-%", death_year);
        append(sb, ")");
    }
    
    for 1..generation-1 append(sb, "  ");
    print(sb, "%/% ", generation, order);
    print_person(sb, row);
    
    for spouses {
        append(sb, " ... ");
        print_person(sb, it);
    }
    append(sb, "\n");
    
    for children family_tree_to_text(sb, it, generation+1, it_index+1);
}

draw_family_tree :: (_r: Rect, using tree: Family_Subtree, loc := #caller_location) -> Rect {
    SPOUSE_GAP_UNITS   := 1.0 + SIBLING_GAP_UNITS;
    COUPLE_WIDTH_UNITS := 1.0 + SPOUSE_GAP_UNITS;  // Derived - width of a married couple

    r := _r;

    draw_person(r, row, loc);
    b := _r;

    if spouses {
        assert(spouses.count == 1, "TODO: multiple spouses");
        spouse := spouses[0];

        // Spouse
        sr := r;
        sr.x += SPOUSE_GAP_UNITS * sr.w;
        draw_person(sr, spouse, loc);
        b = bound(b, sr);

        thick := CONNECT_THICKNESS_FACTOR * min(r.w, r.h);
        connect_color :: Vector4.{0.5, 0.5, 0.5, 1};

        // Horizontal marriage line
        connect: Rect;
        connect.x = r.x + r.w;
        connect.y = r.y + 0.5*(r.h - thick);
        connect.w = sr.x - connect.x;
        connect.h = thick;
        set_shader_for_color();
        immediate_rect(connect, connect_color);

        generation_gap := GENERATION_GAP_UNITS * r.h;

        if children {
            // Calculate total children group width
            total_group_units := 0.0;
            for children total_group_units += it.layout.width_units;
            
            if children.count > 1 then total_group_units += (children.count - 1) * SIBLING_GAP_UNITS;

            children_group_w := total_group_units * r.w;
            couple_mid_x     := r.x + 0.5 * COUPLE_WIDTH_UNITS * r.w;
            first_bound_left := couple_mid_x - 0.5 * children_group_w;

            // Main vertical stem down from marriage
            stem: Rect;
            stem.x = couple_mid_x - thick*0.5;
            stem.y = connect.y + thick;
            stem.w = thick;
            stem.h = 0.5*r.h - 4*thick + 0.5*generation_gap;
            immediate_rect(stem, connect_color);

            // Draw children + connectors
            cr := _r;
            cr.y += generation_gap;

            current_bound_left := first_bound_left;
            
            for child: children {
                person_x := current_bound_left + child.layout.left_overhang_units * r.w;
                cr.x = person_x;

                // Per-child connector ===
                child_mid_x := cr.x + 0.5 * cr.w;

                // Horizontal bar from stem to child
                h: Rect;
                h.y = stem.y + stem.h - thick;
                h.h = thick;

                if child_mid_x < stem.x {
                    h.x = child_mid_x - thick*0.5;
                    h.w = stem.x - child_mid_x + thick*0.5;
                } else {
                    h.x = stem.x;
                    h.w = child_mid_x - stem.x + thick*0.5;
                }
                immediate_rect(h, connect_color);

                // Vertical drop to child
                v: Rect;
                v.x = child_mid_x - thick*0.5;
                v.y = h.y + thick*0.5;
                v.w = thick;
                v.h = cr.y - v.y;
                immediate_rect(v, connect_color);

                new_bound := draw_family_tree(cr, child, loc);
                b = bound(b, new_bound);

                current_bound_left += child.layout.width_units * r.w + SIBLING_GAP_UNITS * r.w;
            }
        }
    }
    return b;
}

REPORT_LEAKS :: false;
fps := 60;
my_theme: Overall_Theme;
db: SQLite_Context;
main :: () {
    #if REPORT_LEAKS defer {
        report := make_leak_report({scan_leaks_to_combine=false});
        log_leak_report(report);
        #if #run array_find(METAPROGRAM_PLUGINS, "Autorun(run_debugger)") debug_break();
    }
    
    #if OS == .WINDOWS {
        Windows.SetProcessDPIAware();
        Windows.timeBeginPeriod(1);
    }
    
    if false
    context.allocator.proc = (mode: Allocator_Mode, requested_size: s64, old_size: s64, old_memory: *void, allocator_data: *void) -> *void {
        debug_break();
        return context.default_allocator.proc(mode, requested_size, old_size, old_memory, allocator_data);
    }
    
    #if OS == .WINDOWS {
        Windows :: #import "Windows";
        if   Windows.IsDebuggerPresent()
        then context.logger = (m: string, _: *void, info: Log_Info) {
            if info.common_flags
            then Windows.OutputDebugStringA(tprint("[%] %\n\0", info.common_flags, m).data);
            else Windows.OutputDebugStringA(tprint("%\n\0", m).data);
        }
    }
    
    set_printer(
        math_struct_printer,
        table_content_printer,
        memory_size_printer,
    );
    
    #if OS == .ANDROID {
        cwd := to_string(Android.android_app.activity.internalDataPath);
    } else {
        cwd := path_strip_filename(get_path_of_running_executable());
    }
    set_working_directory(cwd);
    set_allocators(*family_tree.pool,, context.default_allocator);
    
    zero_bytes(*tweaker_theme.scrollable_region_theme.margin_flags);
    // zero_bytes(*tweaker_theme.scrollable_region_theme.region_background);
    // zero_bytes(*tweaker_theme.scrollable_region_theme.scrollbar_background);
    tweaker_theme.scrollable_region_theme.region_background.shape.roundedness = 0;
    tweaker_theme.scrollable_region_theme.region_background.color = my_theme.background_color;
    tweaker_theme.label_theme.alignment = .Left;
    
    // #if DO_DTC
    // then window.handle = DTC.create_dangerous_window(window.width, window.height, "Family Tree");
    // else window.handle = create_smooth_resize_window(window.width, window.height, "Family Tree", update, *last_time, fps);
    window.handle = create_window(window.width, window.height, "Rodoslov");
    
    heap := context.default_allocator;
    
    set_render_target(window.handle, .LEFT_HANDED,, heap);
    // font_data, ok := read_entire_file("FiraSans-Regular.ttf",, heap);
    // assert(ok);
    // ui_init(xx font_data,, heap);
    ui_init(,, heap);
    
    
    quit := false;
    while !quit {
        profiler_frame_mark();
        #if DO_DTC {
            input_state = DTC.update_dangerous_window_events();
            using input_state;
        } else {
            update_window_events(,, heap);
        }
        
        active := GetRect.active_widget; // I am losing my mind why is this an error when inlined below?????????
        for events_this_frame {
            getrect_handle_event(it,, heap);
            if it.type == {
            case .QUIT; quit = true;
            case .KEYBOARD; if it.key_pressed if it.key_code == {
                case .ESCAPE; active_widget_deactivate_all();
                case #char "T"; if !active then tweaking = !tweaking;
                case #char "C"; if !active {
                    assert(family_tree.dirty == .CLEAN);
                    
                    // Match the constants and k formula used in update().
                    w :: 2.5;
                    h :: 0.5;
                    f :: 5;
    
                    w_box : float : 4.5;  // must match `w` in update()
                    k_now : float = 0.025 * window.width;
                    cx    : float = 0.5   * window.width;
                    cy    : float = 0.5   * window.height;
                    
                    z_fit : float = (1.0 * window.width) /
                                    (family_tree.root.layout.width_units * w_box * k_now);
                    Clamp(*z_fit, 0.1, ZOOM_FACTOR_MAX);
                    zoom_target = z_fit;

                    box_w := w_box * k_now * z_fit;
                    box_h :=         k_now * z_fit;   // h=1, f=1 — matches update()

                    t_x := (cx - 1.25 * box_w - cx) * z_fit + cx;  // = -1.25*box_w*z_fit + cx
                    t_y := (k_now - cy) * z_fit + cy;

                    tree_center_x := t_x + (family_tree.root.layout.width_units * 0.5
                                            - family_tree.root.layout.left_overhang_units) * box_w;
                    shift_x := cx - tree_center_x;

                    n_gens        := family_tree.depth.(float);
                    tree_h_px     := box_h * (1.0 + (n_gens - 1.0) * GENERATION_GAP_UNITS);
                    tree_center_y := t_y + tree_h_px * 0.5;
                    shift_y       := cy - tree_center_y;

                    root_offset.xy = .{shift_x / z_fit, shift_y / z_fit};
                }
            }
            case .MOUSE_WHEEL; if it.wheel_delta && !edit.open && !tweaking {
                factor := it.wheel_delta / cast(float) it.typical_wheel_delta;
                zoom := pow(1.1, factor);
                zoom_target *= zoom;
                Clamp(*zoom_target, ZOOM_FACTOR_MIN, ZOOM_FACTOR_MAX);
            }
            }
        }
        
        update();
        // sleep_milliseconds(10);
        // sleep_to_next_frame(fps);
    }
}

transform :: inline (p: Vector2, center: Vector2) -> Vector2 {
    return (p - center) * root_offset.z + center + root_offset.xy * root_offset.z;
}

ZOOM_FACTOR_MAX :: 50.0;
ZOOM_FACTOR_MIN :: 0.01;
zoom_target := 1.0;
root_offset := Vector3.{z=1.0}; // xy is position and z is zoom
dragging := false;
k: float;

// #if OS == .ANDROID software_keyboard_enabled := false;

current_time: float64;
last_time: float64;
update :: () {
    defer reset_temporary_storage();
    
    current_time = seconds_since_init();
    dt := cast(float)(current_time - last_time);
    Clamp(*dt, 0, 0.1);
    last_time = current_time;
    
    #if DO_DTC {
        get_resizes :: DTC.get_window_resizes;
        using input_state;
        // Key_Code :: type_of)
    } else {
        get_resizes :: get_window_resizes;
    }
    
    for get_resizes(,, context.default_allocator) {
        update_window(it.window);
        if it.window == window.handle {
            window.width  = it.width;
            window.height = it.height;
        }
    }
    
    can_drag := !GetRect.some_widget_received_left_mouse_button && !edit.open && !GetRect.is_grabbing();
    
    if input_button_states[Key_Code.MOUSE_BUTTON_LEFT] & .START && can_drag
    then dragging = true;
    
    if input_button_states[Key_Code.MOUSE_BUTTON_LEFT] & .END && can_drag
    then dragging = false;
    
    if input_button_states[Key_Code.MOUSE_BUTTON_LEFT] & .DOWN && dragging && can_drag {
        delta := Vector2.{xx mouse_delta_x, xx mouse_delta_y};
        #if OS == .ANDROID delta.y *= -1; // dragging needs to be inverted on a touch screen to feel nice....
        root_offset.xy += delta * 1/root_offset.z;
    }
    
    GetRect.move_toward(*root_offset.z, zoom_target, dt, root_offset.z*10, root_offset.z*10);
    
    {
        profiler_zone("Setup");
        my_theme = default_theme_procs[Default_Themes.Default]();
        ui_per_frame_update(window.handle, xx window.width, xx window.height, current_time,, context.default_allocator);
        set_default_theme(my_theme);
        
        bg_col := my_theme.background_color;
        clear_render_target(bg_col.x, bg_col.y, bg_col.z, 1);
        k = 0.025 * window.height;//window.height;//min(window.width, window.height);
    }
    
    defer {
        push_allocator(context.default_allocator);
        profiler_zone("Blit");
        draw_popups();
        maybe_toggle_software_keyboard();
        swap_buffers(window.handle);  
    }
    
    
    profiler_zone("Frame");
    w :: 4.5;
    h :: 1;
    f :: 5;
    r: Rect = ---;
    r.w = w*f*k*root_offset.z;
    r.h = h*f*k*root_offset.z;
    
    p := Vector2.{window.width*0.5-1.25*r.w, k};
    c := Vector2.{window.width*0.5, window.height*0.5};
    t := transform(p, c);
    
    
    if #complete family_tree.dirty == {
    case .CLEAN; {
        r.x = t.x;
        r.y = t.y;
        bound := draw_family_tree(r, family_tree.root);
    }
    case .REFLOW; {
        using family_tree;
        family_tree.dirty = .CLEAN;
        reset(*family_tree.pool);
        assert(family_tree.root_id != xx -1);
        root, depth = family_tree_from_sqlite(*db, root_id,, Allocator.{pool_allocator_proc, xx *pool});
        family_tree_compute_layout(*root);
    }
    case .CHOOSE_ROOT; {
        status, roots := get_roots(*db,, temp);
        assert(status == .OK);
        if !roots {
            if !edit.open open_edit_subwindow(.ROOT);
        } else {
            width := window.width*0.25;
            rect := Rect.{ (window.width-width)*0.5, 3*k, width, 2*k };
            for id: roots {
                status, person := get_person(*db, id,, temp);
                assert(status == .OK);
                full := get_full_name(person,, temp);
                if GetRect.button(rect, full, *my_theme.button_theme, identifier = xx id,, context.default_allocator) {
                    using family_tree;
                    root_id     = id;
                    dirty       = .CLEAN;
                    root, depth = family_tree_from_sqlite(*db, id,, Allocator.{pool_allocator_proc, xx *pool});
                    family_tree_compute_layout(*root);
                }
                rect.y += rect.h;
            }
        }
    }
    }
    
    push_state(context.allocator, context.default_allocator);
    
    if tweaking {
        tweaker_size := window.width * 0.40;
        tweaker_rect := Rect.{ window.width-tweaker_size, 0.5*k, tweaker_size, window.height-k};
        tweaker(tweaker_rect, 0.75*k, *tweaks, *tweaker_theme);
    }
    
    if edit.open {
        add_subwindow(*edit.subwindow, *my_theme.subwindow_theme);
    } else if edit.active {
        reset_edit_subwindow();
    }
    
    sw_theme := my_theme.subwindow_theme;
    sw_theme.subwindow_flags &= ~.VISIBLE_RESIZE_CORNER;
    sw_theme.resize_controls  = 0;
    sw_theme.title_bar_size   = 0.02;
    if options_subwindow.open then add_subwindow(*options_subwindow, *sw_theme);
}

tweaker_theme: Tweaker_Theme;
tweaking := false;

using tweaks: struct {
    SIBLING_GAP_UNITS        : float = 0.15; @Slider(0.1,10,0.1)
    GENERATION_GAP_UNITS     : float = 4.50; @Slider(0.1,10,0.1)
    CONNECT_THICKNESS_FACTOR : float = 0.15; @Slider(0.1,10,0.1) // Thickness of connection lines relative to box size
}

Family_Subtree_Layout :: struct {
    width_units: float;          // subtree width in "person-box units" (1.0 = r.w)
    left_overhang_units: float;  // how much the bound extends left of the person's r.x
};

draw_person :: (_r: Rect, using person: Person_Row, loc := #caller_location) {
    r := _r;
    push_state(context.allocator, context.default_allocator);
    
    theme := my_theme.button_theme;
    if gender[gender.count-1] == {
    case "M"; theme.surface_color = .{.1, .1, .7, 1};
    case "F"; theme.surface_color = .{.7, .1, .1, 1};
    case "N"; theme.surface_color = .{.7, .1, .7, 1};
    case; assert_helper("Invalid gender identifier %", gender);
    }
    
    pressed, state := button(r, "", *theme, xx id, loc);
    if pressed {
        x, y, ok := get_mouse_pointer_position(window.handle, false);
        assert(ok);
        options_key = id;
        options_subwindow.open = true;
        options_subwindow.rect = { xx x, xx y, k*15, k*10 }; // TODO: clip to inside window
    }
    
    r.h /= 2;
    sb: String_Builder;
    
    print_full_name(*sb, person);
    core_draw_button_label(r, builder_to_string(*sb,, temp),  state, *theme);
    r.y += r.h;
    
    append(*sb, birth_year);
    if death_year print(*sb, " - %", death_year);
    core_draw_button_label(r, builder_to_string(*sb,, temp),  state, *theme);
    r.y += r.h;
}

options_key: Person_Key;
options_subwindow := Subwindow_Info.{ open = false, draw = draw_options_buttons, };
draw_options_buttons :: (state: *Subwindow_State, content_rect: Rect, user_data: *void) {
    status, has_parents := has_parents(*db, options_key);
    assert(status == .OK);
    
    r := content_rect;
    r.h /= ifx has_parents then 3 else 4;
    theme := my_theme.button_theme;
    theme.alignment = .Left;
    
    if button(r, "Add Spouse", *theme) {
        open_edit_subwindow(.SPOUSE, options_key);
        options_subwindow.open = false;
    }
    r.y += r.h;
    
    if !has_parents {
        if button(r, "Add Parent", *theme) {
            open_edit_subwindow(.PARENT, options_key);
            options_subwindow.open = false;
        }
        r.y += r.h;
    }
    
    if button(r, "Add Child", *theme) {
        open_edit_subwindow(.CHILD, options_key);
        options_subwindow.open = false;
    }
    r.y += r.h;
    
    
    if button(r, "Edit", *theme) {
        open_edit_subwindow(.EDIT, options_key);
        options_subwindow.open = false;
    }
    r.y += r.h;
    
}


edit: struct {
    using subwindow := Subwindow_Info.{ open = false, draw = draw_edit_subwindow, };
    subwindow_states: [5]*Text_Input_State;
    mode: enum { ROOT; SPOUSE; CHILD; EDIT; PARENT; };
    active: bool;
    
    // use a first class heap instead of a pool because we alloc and
    // free strings when editing fields, but still want to free all
    // live ones when we reset the subwindow.
    heap: Allocator; 
    
    // TODO: this can just be Person
    full_name: string;
    
    gender: Gender;
    birth_year: string;
    death_year: string;
    
    // TODO: these two would fuse when making the struct
    relation: Person_Key;    // key to another person if spouse or child
    id: Person_Key; // for mode == .EDIT;
    
    // TODO: this can just be Marriage
    married: string;  // for mode == .SPOUSE
    divorced: string; // for mode == .SPOUSE
};

doxx_protection :: false;

print_full_name :: (sb: *String_Builder, using person: Person_Row, escape_quotes := false) {
    if doxx_protection {
        print(sb, "Person #%", id);
        return;
    }
    
    if !escape_quotes {
        if middle_name
        then print(sb, "% % %", first_name, middle_name, last_name);
        else print(sb, "% %", first_name, last_name);
    } else {
        append :: (s: string) #expand {
            for 0..s.count-1 {
                c := s[it];
                if c == {
                case 34;   append(sb, "\\\"".data, 2);
                case;      append(sb, *c, 1);
                }
            }
        }
        
        append(first_name);
        append(sb, " ");
        append(middle_name);
        if middle_name append(sb, " ");
        append(last_name);
    }
}

get_full_name :: (using person: Person_Row) -> string {
    sb: String_Builder;
    print_full_name(*sb, person);
    return builder_to_string(*sb);
}

open_edit_subwindow :: (mode: type_of(edit.mode), relation: Person_Key = -1) {
    if doxx_protection {
        log_error("Cannot open edit subwindow when running in dox protection mode!");
        return;
    }
    
    using,except(mode, relation) edit;
    reset_edit_subwindow();
    active = true;
    
    edit.mode     = mode;
    edit.relation = relation;
    
    if mode == .EDIT {
        status, base := get_person(*db, relation,, temp);
        assert(status == .OK);
        
        id        = base.id;
        full_name = get_full_name(base);
        
        line := base.gender;
        gender =, ok := parse_enum(*line, Gender);
        assert(ok);
        modify_string(*birth_year, base.birth_year);
        modify_string(*death_year, base.death_year);
    }
    
    open = true;
    rect.h = min(0.9*window.height, 20*k);
    rect.w = min(0.9*window.width, 7.5*rect.h);
    rect.x = 0.5*(window.width - rect.w);
    rect.y = 0.5*(window.height - rect.h);
}

reset_edit_subwindow :: () {
    using edit;
    
    for *subwindow_states if it.* {
        reset(it.*);
        it.* = null;
    }
    
    // using person;
    active = false;
    if full_name  then free(full_name);     full_name  = "";
    if birth_year then free(birth_year);    birth_year = "";
    if death_year then free(death_year);    death_year = "";
    if married    then free(married);       married    = "";
    if divorced   then free(divorced);      divorced   = "";
}

draw_edit_subwindow :: (state: *Subwindow_State, content_rect: Rect, _: *void) {
    using edit;
    
    total_fields := ifx mode == .SPOUSE
        then subwindow_states.count + 2
        else subwindow_states.count + 2 - 2;
        
    has_other_parent := false;
    other_parent_key: Person_Key;
    if mode == .CHILD {
        result, spouses := get_spouses(*db, relation,, temp);
        assert(result == .OK);
        if spouses.count == {
        case 0; // do nothing
        case 1; other_parent_key = spouses[0].id;
        case;   total_fields += 1; // TOOD: we need to add a dropdown to select who the other parent is
        }
    }
    
    r   := content_rect;
    r.h /= total_fields;
    r_label, r_input := cut_left(r, r.w*0.3);
    
    state_index := 0;
    capture := false;
    input :: (text: string, field: *string, loc := #caller_location) #expand {
        theme := my_theme.label_theme;
        theme.alignment = .Left;
        label(r_label, text, *theme);
        
        last := capture;
        result_action, _, state := text_input(r_input, field.*, *my_theme.text_input_theme, loc = loc);
        capture = result_action == .ENTERED || (state.active && !capture && (input_button_states[Key_Code.TAB] & .START));
        if last {
            activate(state);
            state.last_keypress_time = current_time;
            state.current_click_time = current_time;  // Handle a multiclick next time we draw.
            start_selecting(state);
        }
        
        if   result_action & .TEXT_MODIFIED
        then modify_string(field, state.text);
        
        r.y       += r.h;
        r_label.y += r.h;
        r_input.y += r.h;
        
        subwindow_states[state_index] = state;
        state_index += 1;
    }
    
    valid := true;
    error_text := "";
    validate :: (cond: bool, text: string) #expand {
        valid &&= cond;
        if !error_text && !valid then error_text = text;
    }
    
    input("Name: ", *full_name);
    parts := split(full_name, " ",, temp);
    validate(parts.count == 2 || parts.count == 3, "Name must be exactly two or three word.");
    
    theme := my_theme.label_theme;
    theme.alignment = .Left;
    label(r_label, "Gender:", *theme);
    dropdown(r_input, type_info(type_of(gender)).names, xx *gender);
    r.y       += r.h;
    r_label.y += r.h;
    r_input.y += r.h;
    
    input("Birth:", *birth_year);
    validate(validate_year(birth_year), "Birth year must be a number");
    
    input("Death:", *death_year);
    validate(!death_year || validate_year(death_year), "Death year must be a number or empty");
    
    if mode == .SPOUSE {
        input("Married:", *married);
        validate(validate_year(married), "Marriage year must be a number");
        
        input("Divorced:", *divorced);
        validate(!divorced || validate_year(divorced), "Divorce year must be a number or empty");
    }
    
    if button(r, ifx valid then "Enter" else error_text, *my_theme.button_theme, disable_over=!valid, disable_press=!valid) {
        open = false;
        family_tree.dirty = ifx mode == .PARENT then .CHOOSE_ROOT else .REFLOW;
        g  := type_info(type_of(gender)).names[gender];
        fn := parts[0];
        mn := ifx parts.count == 3 then *parts[1];
        ln := parts[ifx parts.count == 3 then 2 else 1];
        if #complete mode == {
        case .EDIT; {
            result := update_person(*db, id, fn, mn, ln, g, birth_year, ifx death_year then *death_year);
            assert(result == .OK);
        }
        case .ROOT; {
            result := add_person(*db, fn, mn, ln, g, birth_year, ifx death_year then *death_year);
            assert(result == .OK);
            family_tree.root_id = xx sqlite3_last_insert_rowid(db.connections.family);
        }
        case .PARENT; {
            result := add_person(*db, fn, mn, ln, g, birth_year, ifx death_year then *death_year);
            assert(result == .OK);
            key   := sqlite3_last_insert_rowid(db.connections.family).(Person_Key);
            result = add_child(*db, key, relation);
            assert(result == .OK);
        }
        case .SPOUSE; {
            result := add_person(*db,
                fn, mn, ln, g, birth_year, ifx death_year then *death_year
            );
            assert(result == .OK);
            
            key := sqlite3_last_insert_rowid(db.connections.family);
            result = add_marriage(*db, xx key, relation, married, ifx divorced then *divorced);
            assert(result == .OK);
            
            // TODO: we should automatically add parent_child relations if there is only a single spouse bc now we drop those whoops.....
        }
        case .CHILD; {
            result := add_person(*db,
                fn, mn, ln, g, birth_year, ifx death_year then *death_year
            );
            assert(result == .OK);
            
            key := sqlite3_last_insert_rowid(db.connections.family);
            result = add_child(*db, relation, xx key);
            assert(result == .OK);
            if has_other_parent {
                result = add_child(*db, other_parent_key, xx key);
                assert(result == .OK);
            }
        }
        }
    }
}


Gender :: enum s32 {
    M;
    F;
    MtF;
    MtN;
    FtM;
    FtN;
}

validate_gender :: (gender: string) -> bool {
    if gender == {
    case "M";   return true;
    case "F";   return true;
    case "MtF"; return true;
    case "MtN"; return true;
    case "FtM"; return true;
    case "FtN"; return true;
    case; return false;
    }
}

validate_year :: (iso: string) -> bool {
    if iso.count != 4    return false;
    if !is_digit(iso[0]) return false;
    if !is_digit(iso[1]) return false;
    if !is_digit(iso[2]) return false;
    if !is_digit(iso[3]) return false;
    return true;
}

immediate_rect :: inline (using r: Rect, c: Vector4) { immediate_quad(x, y, x+w, y+h, c); }

modify_string :: (ps: *string, new_value: string) {
    free(ps.*);
    ps.* = copy_string(new_value);
}

#insert #run,host -> string { #import "ncz/SQLite"; return generate_schema_bindings({},
{
    name = "family",
    path = "family.sqlite3",    
    init = #string _SQLITE
pragma journal_mode = WAL;
pragma synchronous  = NORMAL;
pragma foreign_keys = ON;
pragma temp_store   = MEMORY;

create table if not exists persons (
  id          integer primary key autoincrement,
  first_name  text not null,
  middle_name text,
  last_name   text not null,
  gender      text not null,
  birth_year  date not null,
  death_year  date
);

create table if not exists marriages (
  id            integer primary key autoincrement,
  person1_id    integer not null,
  person2_id    integer not null,
  marriage_date date    not null,
  divorce_date  date,
  
  foreign key (person1_id) references persons(id),
  foreign key (person2_id) references persons(id),
  check (person1_id < person2_id)
);

create table if not exists parent_child (
  id        integer primary key autoincrement,
  parent_id integer not null,
  child_id  integer not null,
  
  foreign key (parent_id) references persons(id),
  foreign key (child_id)  references persons(id),
  unique (parent_id, child_id)
);

create index if not exists idx_persons_name        on persons      (last_name, middle_name, first_name);
create index if not exists idx_marriages_person1   on marriages    (person1_id);
create index if not exists idx_marriages_person2   on marriages    (person2_id);
create index if not exists idx_parent_child_parent on parent_child (parent_id);
create index if not exists idx_parent_child_child  on parent_child (child_id);
    _SQLITE,
    procedures = .[

{ #code add_person :: (first: string, middle: *string, last: string, gender: string, birth: string, death: *string), #string _SQLITE
    insert  into
    persons (first_name, middle_name, last_name, gender, birth_year, death_year)
    values  (?, ?, ?, ?, ?, ?)
_SQLITE },

{ #code update_person :: (key: Person_Key, first: string, middle: *string, last: string, gender: string, birth: string, death: *string), #string _SQLITE
    insert  into
    persons (id, first_name, middle_name, last_name, gender, birth_year, death_year)
    values  (?, ?, ?, ?, ?, ?, ?)
    on conflict(id) do update set
      first_name  = excluded.first_name,
      middle_name = excluded.middle_name,
      last_name   = excluded.last_name,
      gender      = excluded.gender,
      birth_year  = excluded.birth_year,
      death_year  = excluded.death_year;
_SQLITE },

{ #code get_person :: (id: Person_Key) -> (Person_Row), "select * from persons where id = ?" },

{ #code add_child :: (parent: Person_Key, child: Person_Key), "insert into parent_child (parent_id, child_id) values (?, ?)" }, 

{ #code add_marriage :: (p1: Person_Key, p2: Person_Key, start: string, end: *string), #string _SQLITE
    insert into marriages (person1_id, person2_id, marriage_date, divorce_date)
    values (
      case when ?1 < ?2 then ?1 else ?2 end,
      case when ?1 < ?2 then ?2 else ?1 end,
      ?3,
      ?4
    );
_SQLITE },

{ #code get_children_keys :: (p1: Person_Key, p2: Person_Key) -> ([]Person_Key), #string _SQLITE
    select id
    from   persons
    where  id in (
      select child_id
      from   parent_child 
      where  parent_id in (?1, ?2)
    )
    order by birth_year
_SQLITE },

{ #code get_spouses :: (id: Person_Key) -> ([]Person_Row), #string _SQLITE
    select * from persons where id = (
        select case
          when m.person1_id = ?1 then m.person2_id
          else m.person1_id
        end as spouse_id
        from   marriages m
        where  (m.person1_id = ?1 or m.person2_id = ?1)
    )
_SQLITE },

{ #code has_parents :: (key: Person_Key) -> (bool), #string _SQLITE
    select 1 from parent_child
    where child_id = ?1
_SQLITE
},

{ #code get_roots :: () -> ([]Person_Key), #string _SQLITE
    with root_persons as (
        select id from persons p
        where not exists (
            select 1 from parent_child pc where pc.child_id = p.id
        )
        and not exists (
            select 1 from marriages m
            where (m.person1_id = p.id or m.person2_id = p.id)
            and exists (
                select 1
                from   parent_child pc
                where  pc.child_id = case 
                                       when m.person1_id = p.id then m.person2_id
                                       else m.person1_id
                                     end
            )
        )
    )
    select distinct coalesce(m.person1_id, rp.id) as id
    from root_persons rp
    left join marriages m on (m.person1_id = rp.id or m.person2_id = rp.id)
    order by (select p.birth_year from persons p where p.id = coalesce(m.person1_id, rp.id))
_SQLITE },

    ]
}
);};

using GetRect :: #import "GetRect_LeftHanded";
using Basic   :: #import "Basic"()(MEMORY_DEBUGGER=!true);
#import "Compiler";
#import "Math";
#import "Pool";
#import "String";
#import "System";
#import "File";
#import "Hash_Table";
#import "Simp";
#import "ncz/SQLite";
#import "ncz/Util";
#import "ncz/Tweaker";
#import "Thread";


#if #run array_find(METAPROGRAM_PLUGINS, "ncz/tracy") {
    profiler_frame_mark :: context._Tracy.FrameMark;
    profiler_zone       :: context._Tracy.ZoneScoped;
} else {
    profiler_frame_mark :: () #expand #no_debug {}
    profiler_zone       :: ($_ := "", _ := "", _: u32 = 0, _: u64 = 0, _ := #caller_location) #expand #no_debug {}
}



#if OS != .ANDROID maybe_toggle_software_keyboard :: () { }
#if OS == .ANDROID {
last_click: float64;
last_active_widget: *GetRect.Active_Widget;
maybe_toggle_software_keyboard :: () {
    w := GetRect.active_widget;
    
    is_input  := w && w.widget_type == GetRect.Text_Input_State;
    was_input := last_active_widget && last_active_widget.widget_type == GetRect.Text_Input_State;
    
    if is_input && last_click != w.(*Text_Input_State).last_click_time then toggle_software_keyboard(true);
    else if is_input != was_input                                      then toggle_software_keyboard(is_input);
    
    if is_input then last_click = w.(*Text_Input_State).last_click_time;
    last_active_widget = w;
}

Android :: #import "Android"()(DEFINE_ANDROID_MAIN_AND_CALL_THIS=main);
toggle_software_keyboard :: (enable: bool) {
    using Android;

    vm  := Android.android_app.activity.vm;
    env :  *JNIEnv;

    attach := JavaVMAttachArgs.{
        version = JNI_VERSION_1_6,
        name    = "NativeThread",
        group   = null,
    };
    
    result := vm.*.AttachCurrentThread(vm, *env, *attach);
    if (result == JNI_ERR) {
        log_error("Could not attach to current thread");
        return;
    }

    // Retrieves NativeActivity.
    activity := Android.android_app.activity.clazz;
    class    := env.*.GetObjectClass(env, activity);

    // Context.INPUT_METHOD_SERVICE.
    class_ctx := env.*.FindClass(env,"android/content/Context");
    input_method_service_filed := env.*.GetStaticFieldID(env, class_ctx, "INPUT_METHOD_SERVICE", "Ljava/lang/String;");
    input_method_service       := env.*.GetStaticObjectField(env, class_ctx, input_method_service_filed);
    // JniCheck(input_method_service);

    // getSystemService(Context.input_method_service).
    input_manager_class        := env.*.FindClass(env, "android/view/inputmethod/InputMethodManager");
    get_system_service_method  := env.*.GetMethodID(env, class, "getSystemService", "(Ljava/lang/String;)Ljava/lang/Object;");
    input_method_manager       := env.*.CallObjectMethod(env, activity, get_system_service_method, input_method_service);

    // getWindow().getDecorView().
    get_window_method     := env.*.GetMethodID(env, class, "getWindow", "()Landroid/view/Window;");
    window                := env.*.CallObjectMethod(env, activity, get_window_method);
    window_class          := env.*.FindClass(env, "android/view/Window");
    get_decor_view_method := env.*.GetMethodID(env, window_class, "getDecorView", "()Landroid/view/View;");
    decor_view            := env.*.CallObjectMethod(env, window, get_decor_view_method);

    flags: jint = 0;
    if (enable) {
        // input_method_manager.showSoftInput(...).
        MethodShowSoftInput := env.*.GetMethodID(env, input_manager_class, "showSoftInput", "(Landroid/view/View;I)Z");
        result              := env.*.CallBooleanMethod(env, input_method_manager, MethodShowSoftInput, decor_view, flags);
    //     JniCheck(result);
    } else {
        // Runs window.getViewToken()
        view_class              := env.*.FindClass(env, "android/view/View");
        get_window_token_method := env.*.GetMethodID(env, view_class, "getWindowToken", "()Landroid/os/IBinder;");
        binder                  := env.*.CallObjectMethod(env, decor_view, get_window_token_method);

        // input_method_manager.hideSoftInput(...).
        hide_soft_input_method := env.*.GetMethodID(env, input_manager_class, "hideSoftInputFromWindow", "(Landroid/os/IBinder;I)Z");
        result                 := env.*.CallBooleanMethod(env, input_method_manager, hide_soft_input_method, binder, flags);
    //     JniCheck(result);
    }
}

is_software_keyboard_enabled :: () -> bool {
    using Android;

    vm  := Android.android_app.activity.vm;
    env :  *JNIEnv;

    attach := JavaVMAttachArgs.{
        version = JNI_VERSION_1_6,
        name    = "NativeThread",
        group   = null,
    };
    
    result := vm.*.AttachCurrentThread(vm, *env, *attach);
    if (result == JNI_ERR) {
        log_error("Could not attach to current thread");
        return false;
    }

    // Retrieves NativeActivity.
    activity := Android.android_app.activity.clazz;
    class    := env.*.GetObjectClass(env, activity);

    // Context.INPUT_METHOD_SERVICE.
    class_ctx := env.*.FindClass(env, "android/content/Context");
    input_method_service_field := env.*.GetStaticFieldID(env, class_ctx, "INPUT_METHOD_SERVICE", "Ljava/lang/String;");
    input_method_service       := env.*.GetStaticObjectField(env, class_ctx, input_method_service_field);

    // getSystemService(Context.input_method_service).
    input_manager_class       := env.*.FindClass(env, "android/view/inputmethod/InputMethodManager");
    get_system_service_method := env.*.GetMethodID(env, class, "getSystemService", "(Ljava/lang/String;)Ljava/lang/Object;");
    input_method_manager      := env.*.CallObjectMethod(env, activity, get_system_service_method, input_method_service);

    // Call isAcceptingText() on InputMethodManager
    is_accepting_text_method := env.*.GetMethodID(env, input_manager_class, "isAcceptingText", "()Z");
    is_accepting := env.*.CallBooleanMethod(env, input_method_manager, is_accepting_text_method);

    return xx is_accepting;
}

}