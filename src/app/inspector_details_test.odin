package main

import "core:testing"
import "core:mem"
import "core:strings"
import "../logic"
import "../config"
import "../localization"
import c "../contracts"

@(test)
inspector_subjects_needs_and_products :: proc(t: ^testing.T) {
    defer free_all(context.temp_allocator)
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena, alignment=64)
    defer mem.dynamic_arena_destroy(&arena)
    text, ok := localization.decode(transmute([]byte)#load("../../assets/localization/en.json"), mem.dynamic_arena_allocator(&arena))
    testing.expect(t, ok)
    text.entries["fixture_resource"] = "Water"
    text.entries["fixture_unit"] = "litres"
    text.entries["fixture_subject"] = "Humans"
    resources := [?]logic.Resource{{id="water", name_key="fixture_resource", unit_type_key="fixture_unit"}}
    types := [?]logic.Subject_Type{{id="human", name_key="fixture_subject"}}
    catalog := config.Catalog{resources=resources[:], subjects=types[:]}
    needs := [?]logic.Need{
        {resource_id="water", amount_per_hour=2, capacity=100},
        {resource_id="water", amount_per_unit=3, capacity=100},
        {resource_id="water", amount_per_resident=4, capacity=100},
    }
    products := [?]logic.Product{
        {resource_id="water", units_per_hour=5, capacity=100},
        {resource_id="water", amount_per_resident=6, capacity=100},
    }
    definition := logic.Building_Type{residents={type="human",capacity=10}, subject_roles=[]logic.Building_Subject_Role{{role_id=.worker,quantity=2,required=true},{role_id=.supervisor,quantity=1,required=true},{role_id=.repairer,quantity=3,required=false}}, needs=needs[:], produces=products[:]}
    stored := [?]logic.Stored_Resource{{resource_id="water",amount=25}}
    instance := logic.Building_Instance{id="home", residents_amount=f32(7), stored=stored[:]}
    roles := [?]logic.Subject_Role{.worker,.supervisor}
    subjects := [?]logic.Runtime_Subject{
        {occupation="home", roles=roles[:], activity=.Inside},
        {occupation="home", roles=roles[:], activity=.Removed},
        {occupation="elsewhere", roles=roles[:], activity=.Inside},
    }
    snapshot := c.Building_Snapshot{id="home"}
    lines := building_info_lines(snapshot, definition, text, instance, catalog, subjects[:])
    for expected in ([?]string{
        "Humans: 7/10 residents", "Workers: 1/2 needed",
        "Supervisors: 1/1 needed", "Repairers: 0/3 needed",
        "Water: 25/100 litres", "2 litres/h",
        "3 litres/product unit", "4 litres/resident/h",
        "5 litres/h", "6 litres/resident/h",
    }) {
        found := false
        for line in lines { if line == expected { found = true } }
        testing.expect(t, found, expected)
    }
    for line in lines { testing.expect(t, !strings.contains(line,"{")) }
    // New frames reflect live resident counts; formatting never mutates source data.
    testing.expect(t, stored[0].amount == 25 && subjects[0].activity == .Inside)
    instance.residents_amount = f32(9)
    lines = building_info_lines(snapshot, definition, text, instance, catalog, subjects[:])
    testing.expect(t, lines[8] == "Humans: 9/10 residents")
    lines = building_info_lines(snapshot, {}, text, {}, catalog, nil)
    testing.expect(t, lines[8] == text.entries["building_info_no_residents"])
    empty_count := 0
    for line in lines { if line == text.entries["building_info_empty"] { empty_count += 1 } }
    testing.expect(t, empty_count == 2)
    no_staff := false
    for line in lines { if line == text.entries["building_info_no_staff"] { no_staff = true } }
    testing.expect(t,no_staff)
    lines = building_info_lines(snapshot,{},text,{},catalog,subjects[:])
    assigned_visible := false
    for line in lines { if line == "Workers: 1/0 needed" { assigned_visible = true } }
    testing.expect(t,assigned_visible)
}
