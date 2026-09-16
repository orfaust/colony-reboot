package main

import "core:testing"
import "../config"
import "../logic"
import c "../contracts"

@(test)
landing_and_individual_subject_projection :: proc(t: ^testing.T) {
    platform := c.Rect{400,300,80,40}
    start := landing_ship_bounds(platform,0)
    end := landing_ship_bounds(platform,1)
    testing.expect(t,start.y == -32 && end.y == 304 && start.width == 32)
    definitions := [?]logic.Subject_Type{{id="human",color={4,5,6}}}
    catalog := config.Catalog{subjects=definitions[:]}
    fleet := logic.Transport_State{}
    fleet.subjects = make([dynamic]logic.Runtime_Subject)
    defer delete(fleet.subjects)
    append(&fleet.subjects,logic.Runtime_Subject{id=1,subject_id="human",activity=.Moving,position={0,0}})
    append(&fleet.subjects,logic.Runtime_Subject{id=2,subject_id="human",activity=.Moving,position={1,0}})
    append(&fleet.subjects,logic.Runtime_Subject{id=3,subject_id="human",activity=.Inside,position={1,0}})
    camera := Camera{zoom=1}
    draws := landing_draws(&fleet,catalog,nil,camera,1280,720)
    testing.expect(t,len(draws) == 1 && len(draws[0].passengers) == 2)
    testing.expect(t,draws[0].passengers[0] == c.Rect{635.5,344,9,16})
    testing.expect(t,draws[0].passengers[1].x > draws[0].passengers[0].x)
    fleet.subjects[0].position.y = 1
    moved := landing_draws(&fleet,catalog,nil,camera,1280,720)
    testing.expect(t,moved[0].passengers[0].y > draws[0].passengers[0].y)
    testing.expect(t,moved[0].passengers[1] == draws[0].passengers[1])
    testing.expect(t,moved[0].subject_color == definitions[0].color)
}
