package localization

import "core:fmt"
import "core:strings"

INSPECTOR_LABEL_KEYS :: [?]string{"building_info_subjects", "building_info_no_residents", "building_info_needs", "building_info_products", "building_info_empty", "building_info_scroll", "info_scroll_hint", "building_info_no_staff"}
INSPECTOR_FORMATS :: [?]struct{key: string, tokens: []string}{
    {"building_info_power_output", {"{value}"}},
    {"building_info_power_need", {"{value}"}},
    {"building_info_residents", {"{name}", "{amount}", "{capacity}"}},
    {"building_info_workers", {"{assigned}", "{required}"}},
    {"building_info_supervisors", {"{assigned}", "{required}"}},
    {"building_info_repairers", {"{assigned}", "{required}"}},
    {"building_info_stock", {"{name}", "{amount}", "{capacity}", "{unit}"}},
    {"building_info_rate_hour", {"{value}", "{unit}"}},
    {"building_info_rate_product", {"{value}", "{unit}"}},
    {"building_info_rate_resident", {"{value}", "{unit}"}},
}

validate_inspector_text :: proc(entries: map[string]string) -> bool {
    for key in INSPECTOR_LABEL_KEYS {
        if strings.trim_space(entries[key]) == "" {
            fmt.eprintf("Localization: missing or empty required key %q.\n", key)
            return false
        }
    }
    for format in INSPECTOR_FORMATS {
        for token in format.tokens {
            if !strings.contains(entries[format.key], token) {
                fmt.eprintf("Localization: %q must contain %s.\n", format.key, token)
                return false
            }
        }
    }
    return true
}
