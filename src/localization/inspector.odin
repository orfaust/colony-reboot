package localization

import "core:fmt"
import "core:strings"

INSPECTOR_LABEL_KEYS :: [?]string{"building_info_subjects", "building_info_no_residents", "building_info_needs", "building_info_products", "building_info_stock_header", "building_info_empty", "building_info_scroll", "info_scroll_hint", "building_info_no_staff", "building_info_staffing", "building_info_individuals", "building_info_no_individuals", "subject_info_unassigned", "subject_info_needs", "subject_info_no_needs", "work_phase_idle", "work_phase_resting", "work_phase_reserved", "work_phase_moving_to_work", "work_phase_working", "work_phase_extra_working", "medical_status_none", "medical_status_pending_evacuation", "medical_status_evacuating", "medical_status_hospitalized", "medical_status_returning", "production_state_operational", "production_state_inactive", "production_state_warming_up", "production_state_unstaffed", "production_state_missing_input", "production_state_output_full"}
INSPECTOR_FORMATS :: [?]struct{key: string, tokens: []string}{
    {"building_info_power_output", {"{value}"}},
    {"building_info_power_need", {"{value}"}},
    {"building_info_residents", {"{name}", "{amount}", "{capacity}"}},
    {"building_info_workers", {"{covered}", "{required}"}},
    {"building_info_supervisors", {"{covered}", "{required}"}},
    {"building_info_repairers", {"{covered}", "{required}"}},
    {"building_info_coverage_reserved", {"{role}", "{reserved}"}},
    {"building_info_coverage_ondemand", {"{role}", "{quantity}"}},
    {"building_info_uncovered", {"{count}"}},
    {"subject_info_identity", {"{name}", "{id}"}},
    {"subject_info_health", {"{value}"}},
    {"subject_info_phase", {"{value}"}},
    {"subject_info_role", {"{value}"}},
    {"subject_info_assignment", {"{value}"}},
    {"subject_info_slot", {"{building}", "{slot}"}},
    {"subject_info_timers", {"{work}", "{max_work}", "{rest}", "{max_rest}", "{idle}"}},
    {"subject_info_medical", {"{value}"}},
    {"subject_info_need_ok", {"{name}", "{value}"}},
    {"subject_info_need_short", {"{name}", "{value}", "{hours}"}},
    {"building_info_stock", {"{name}", "{amount}", "{capacity}", "{unit}"}},
    {"building_info_stock_flow", {"{name}", "{consumed}", "{produced}", "{unit}"}},
    {"building_info_production", {"{value}"}},
    {"building_info_rate_hour", {"{value}", "{unit}"}},
    {"building_info_rate_product", {"{value}", "{unit}"}},
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
