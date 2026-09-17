package main

import "core:testing"
import "core:mem"
import "core:strings"
import "../logic"
import "../config"
import "../localization"
import c "../contracts"

// Task-11 presentation fixture: coverage lines report physical coverage and
// reservations, individuals list health/phase/role/assignment/timers/needs, and
// removed or unrelated subjects never appear. Rendering is not initialized.
@(test)
inspector_shows_coverage_individuals_needs_and_products :: proc(t: ^testing.T) {
    defer free_all(context.temp_allocator)
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena, alignment=64)
    defer mem.dynamic_arena_destroy(&arena)
    text, ok := localization.decode(transmute([]byte)#load("../../assets/config/default/localization/en.json"), mem.dynamic_arena_allocator(&arena))
    testing.expect(t, ok)
    text.entries["fixture_resource"] = "Water"
    text.entries["fixture_resource_meals"] = "Meals"
    text.entries["fixture_unit"] = "litres"
    text.entries["fixture_subject"] = "Humans"
    resources := [?]logic.Resource{
        {id="water", name_key="fixture_resource", unit_type_key="fixture_unit"},
        {id="meals", name_key="fixture_resource_meals", unit_type_key="fixture_unit"},
    }
    types := [?]logic.Subject_Type{{id="human", name_key="fixture_subject", work_time=12, rest_time=12}}
    catalog := config.Catalog{resources=resources[:], subjects=types[:]}
    needs := [?]logic.Need{
        {resource_id="water", amount_per_hour=2, capacity=100},
        {resource_id="water", amount_per_unit=3, capacity=100},
    }
    products := [?]logic.Product{
        {resource_id="water", units_per_hour=5, capacity=100},
        {resource_id="water", units_per_hour=6, capacity=100},
    }
    definition := logic.Building_Type{residents={type="human",capacity=10}, subject_roles=[]logic.Building_Subject_Role{{role_id=.worker,quantity=2,staffing_mode=.continuous},{role_id=.supervisor,quantity=1,staffing_mode=.continuous},{role_id=.repairer,quantity=3,staffing_mode=.on_demand}}, needs=needs[:], produces=products[:]}
    stored := [?]logic.Stored_Resource{{resource_id="water",amount=25}}
    instance := logic.Building_Instance{id="home", residents_amount=f32(7), stored=stored[:]}
    subject_needs: [c.NEED_SLOT_LIMIT]logic.Need_State
    subject_needs[0] = {resource_id="water", fulfillment=1}
    subject_needs[1] = {resource_id="meals", fulfillment=0.5, shortage_hours=2}
    roles := [?]logic.Subject_Role{.worker,.supervisor}
    assignment := c.Shift_Assignment{building_id="home", role_id=.worker, slot_index=0}
    subjects := [?]logic.Runtime_Subject{
        {id=42, subject_id="human", residence="home", roles=roles[:], activity=.Inside, health=0.875, phase=.Working, assignment=assignment, work_hours=3, need_count=2, needs=subject_needs},
        {id=43, subject_id="human", residence="elsewhere", roles=roles[:], activity=.Inside},
        {id=44, subject_id="human", residence="home", roles=roles[:], activity=.Removed},
    }
    coverages: [3]c.Staffing_Coverage
    coverages[0] = {role_id=.worker, required_slots=2, covered_slots=1, reserved_slots=1}
    coverages[1] = {role_id=.supervisor, required_slots=1, covered_slots=1}
    coverages[2] = {role_id=.repairer}
    snapshot := c.Building_Snapshot{id="home"}
    stock := [?]c.Stock_Snapshot{{resource_id="water",amount=25,capacity=100}}
    rates := [?]c.Production_Rate{{resource_id="water",consumed_per_hour=30,produced_per_hour=5}}
    lines := building_info_lines(snapshot, definition, text, instance, catalog, subjects[:], coverages[:], stock[:], .Missing_Input, rates[:])
    for expected in ([?]string{
        "Humans: 7/10 residents",
        text.entries["building_info_staffing"],
        "Workers: 1/2 covered",
        "Worker: 1 arriving",
        "Supervisors: 1/1 covered",
        "Uncovered continuous slots: 1",
        "Repairer: 3 on demand",
        text.entries["building_info_individuals"],
        "Humans #42",
        "Health: 87.5%",
        "Phase: Working",
        "Role: Worker",
        "Assigned: home slot 0",
        "Work 3/12 h | Rest 0/12 h | Idle 0 h",
        "Medical: None",
        "Water: 100%",
        "Meals: 50% (2 h short)",
        "Water: 25/100 litres",
        "Water: 30 in, 5 out (litres/h)",
        "Production: Missing input",
        "2 litres/h",
        "3 litres/product unit",
        "5 litres/h", "6 litres/h",
    }) {
        found := false
        for line in lines { if line == expected { found = true } }
        testing.expect(t, found, expected)
    }
    for line in lines {
        testing.expect(t, !strings.contains(line,"{"), line)
        testing.expect(t, !strings.contains(line,"#43") && !strings.contains(line,"#44"), line)
    }
    // New frames reflect live resident counts; formatting never mutates source data.
    testing.expect(t, stored[0].amount == 25 && subjects[0].activity == .Inside)
    instance.residents_amount = f32(9)
    lines = building_info_lines(snapshot, definition, text, instance, catalog, subjects[:], coverages[:], stock[:], .None, rates[:])
    testing.expect(t, lines[7] == "Humans: 9/10 residents")
    // A building with no resident slot shows no Subjects section, not an empty one.
    lines = building_info_lines(snapshot, {}, text, {}, catalog, nil, nil, nil, .Inactive, nil)
    subjects_section, no_residents := false, false
    for line in lines {
        if line == text.entries["building_info_subjects"] { subjects_section = true }
        if line == text.entries["building_info_no_residents"] { no_residents = true }
    }
    testing.expect(t, !subjects_section && !no_residents)
    no_staff, no_individuals := false, false
    empty_count := 0
    for line in lines {
        if line == text.entries["building_info_no_staff"] { no_staff = true }
        if line == text.entries["building_info_no_individuals"] { no_individuals = true }
        if line == text.entries["building_info_empty"] { empty_count += 1 }
    }
    testing.expect(t, no_staff && no_individuals && empty_count == 3)
    // Individuals still show when coverage is unknown, so the block is never hidden.
    lines = building_info_lines(snapshot, {}, text, {}, catalog, subjects[:], nil, nil, .None, nil)
    individual_visible := false
    for line in lines { if line == "Humans #42" { individual_visible = true } }
    testing.expect(t, individual_visible)
}

// A scheduled replacement with no physical assignment still presents its role and
// target slot, and an individual with no need records shows the localized empty state.
@(test)
inspector_shows_reservation_and_empty_needs :: proc(t: ^testing.T) {
    defer free_all(context.temp_allocator)
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena, alignment=64)
    defer mem.dynamic_arena_destroy(&arena)
    text, ok := localization.decode(transmute([]byte)#load("../../assets/config/default/localization/en.json"), mem.dynamic_arena_allocator(&arena))
    testing.expect(t, ok)
    text.entries["fixture_subject"] = "Humans"
    types := [?]logic.Subject_Type{{id="human", name_key="fixture_subject", work_time=12, rest_time=12}}
    catalog := config.Catalog{subjects=types[:]}
    reservation := c.Shift_Assignment{building_id="home", role_id=.supervisor, slot_index=1}
    subjects := [?]logic.Runtime_Subject{
        {id=7, subject_id="human", residence="home", roles=[]logic.Subject_Role{.supervisor}, activity=.Inside, health=1, phase=.Reserved, reservation=reservation},
    }
    lines := building_info_lines(c.Building_Snapshot{id="home"}, {}, text, {}, catalog, subjects[:], nil, nil, .None, nil)
    for expected in ([?]string{"Humans #7", "Phase: Reserved", "Role: Supervisor", "Assigned: home slot 1", text.entries["subject_info_no_needs"]}) {
        found := false
        for line in lines { if line == expected { found = true } }
        testing.expect(t, found, expected)
    }
}

// Shipped-data regression for the water collector: a type that produces no power
// shows no output row, and a type with no resident slot shows no Subjects section.
@(test)
shipped_water_collector_omits_output_and_subjects :: proc(t: ^testing.T) {
    defer free_all(context.temp_allocator)
    data := load_reload_data(INITIAL_LEVEL_PATH)
    testing.expect(t, data != nil)
    if data == nil { return }
    defer destroy_reload_data(data)
    instance: logic.Building_Instance
    found := false
    for building in data.level.buildings { if building.id == "WC1" { instance = building; found = true } }
    testing.expect(t, found)
    if !found { return }
    definition, definition_found := config.find_building(data.catalog, instance.building_id)
    testing.expect(t, definition_found)
    testing.expect(t, definition.power_output_kw == 0 && !logic.hosts_residents(definition))
    lines := building_info_lines(c.Building_Snapshot{id=instance.id}, definition, data.text, instance, data.catalog, nil, nil, nil, .None, nil)
    has_output, has_subjects, has_residents := false, false, false
    for line in lines {
        if strings.contains(line, "Power produced") { has_output = true }
        if line == data.text.entries["building_info_subjects"] { has_subjects = true }
        if line == data.text.entries["building_info_no_residents"] { has_residents = true }
    }
    testing.expect(t, !has_output && !has_subjects && !has_residents)
}
