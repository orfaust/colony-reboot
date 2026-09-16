package main

import "core:testing"
import "core:math"
import "core:strconv"
import "core:strings"

@(test)
info_numbers_follow_semantic_precision :: proc(t: ^testing.T) {
    defer free_all(context.temp_allocator)
    cases := [?]struct{value: f64, decimals: int, expected: string}{
        {0,2,"0"}, {-0.0,2,"0"}, {12,2,"12"}, {12.5,2,"12.5"},
        {12.345,2,"12.35"}, {12.345,3,"12.345"}, {12.345,1,"12.3"},
        {0.125,1,"0.125"}, {0.0123,2,"0.0123"}, {-0.5,3,"-0.5"},
        {1000000,2,"1000000"}, {f64(f32(0.1)),2,"0.1"},
    }
    for test in cases {
        actual := info_number(test.value,test.decimals)
        testing.expect(t,actual == test.expected,actual)
    }
    testing.expect(t,info_number(0,signed=true) == "0")
    testing.expect(t,info_number(0.5,signed=true) == "+0.5")
    testing.expect(t,info_number(-0.5,signed=true) == "-0.5")
    testing.expect(t,power_text("{value} kW",2.5) == "2.5 kW")
}

@(test)
small_nonzero_values_never_become_zero :: proc(t: ^testing.T) {
    defer free_all(context.temp_allocator)
    for value in ([?]f64{0.049,0.009,0.00049,0.0000001234,1e-30,1e-100,1e-300}) {
        for decimals in 1..<4 {
            for sign in ([?]f64{1,-1}) {
                formatted := info_number(value*sign,decimals)
                parsed, ok := strconv.parse_f64(formatted)
                testing.expect(t,ok && parsed != 0,formatted)
                testing.expect(t,math.abs(parsed-value*sign)/value < 0.005,formatted)
            }
        }
    }
    // Fractional replenishment rates are independent of whole passenger counts.
    line := station_stock_text("{units}/{capacity} {rate}","",2,10.5,0.00001234,context.temp_allocator,true)
    testing.expect(t,strings.has_prefix(line,"2/10 +"))
    testing.expect(t,!strings.has_suffix(line,"+0"))
}
