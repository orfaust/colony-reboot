package main

import "core:fmt"
import "core:math"
import "core:strings"

// Presentation precision only. Simulation values are never rounded or mutated.
// Typical quantities/power: 2 decimals; rates/time: 3; distance/speed: 1.
// Trim trailing zeros. Fractions below one retain 3 significant digits, switching
// to scientific notation when useful, never rounding a small nonzero value to zero.
info_number :: proc(value: f64, decimals: int = 2, allocator := context.temp_allocator, signed: bool = false) -> string {
    if value == 0 { return "0" } // Includes negative zero; no misleading +0/-0.
    magnitude := math.abs(value)
    result: string
    if magnitude < 1 {
        result = fmt.aprintf("%.3g", value, allocator=allocator)
    } else {
        result = fmt.aprintf("%.*f", decimals, value, allocator=allocator)
        if strings.contains(result, ".") {
            result = strings.trim_right(result, "0")
            result = strings.trim_right(result, ".")
        }
    }
    if signed && value > 0 { return fmt.aprintf("+%s", result, allocator=allocator) }
    return result
}
