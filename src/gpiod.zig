pub const struct_gpiod_chip = opaque {};
pub const struct_gpiod_chip_info = opaque {};
pub const struct_gpiod_line_info = opaque {};
pub const struct_gpiod_line_settings = opaque {};
pub const struct_gpiod_line_config = opaque {};
pub const struct_gpiod_request_config = opaque {};
pub const struct_gpiod_line_request = opaque {};
pub const struct_gpiod_info_event = opaque {};
pub const struct_gpiod_edge_event = opaque {};
pub const struct_gpiod_edge_event_buffer = opaque {};
pub extern fn gpiod_chip_open(path: [*c]const u8) ?*struct_gpiod_chip;
pub extern fn gpiod_chip_close(chip: ?*struct_gpiod_chip) void;
pub extern fn gpiod_chip_get_info(chip: ?*struct_gpiod_chip) ?*struct_gpiod_chip_info;
pub extern fn gpiod_chip_get_path(chip: ?*struct_gpiod_chip) [*c]const u8;
pub extern fn gpiod_chip_get_line_info(chip: ?*struct_gpiod_chip, offset: c_uint) ?*struct_gpiod_line_info;
pub extern fn gpiod_chip_watch_line_info(chip: ?*struct_gpiod_chip, offset: c_uint) ?*struct_gpiod_line_info;
pub extern fn gpiod_chip_unwatch_line_info(chip: ?*struct_gpiod_chip, offset: c_uint) c_int;
pub extern fn gpiod_chip_get_fd(chip: ?*struct_gpiod_chip) c_int;
pub extern fn gpiod_chip_wait_info_event(chip: ?*struct_gpiod_chip, timeout_ns: i64) c_int;
pub extern fn gpiod_chip_read_info_event(chip: ?*struct_gpiod_chip) ?*struct_gpiod_info_event;
pub extern fn gpiod_chip_get_line_offset_from_name(chip: ?*struct_gpiod_chip, name: [*c]const u8) c_int;
pub extern fn gpiod_chip_request_lines(chip: ?*struct_gpiod_chip, req_cfg: ?*struct_gpiod_request_config, line_cfg: ?*struct_gpiod_line_config) ?*struct_gpiod_line_request;
pub extern fn gpiod_chip_info_free(info: ?*struct_gpiod_chip_info) void;
pub extern fn gpiod_chip_info_get_name(info: ?*struct_gpiod_chip_info) [*c]const u8;
pub extern fn gpiod_chip_info_get_label(info: ?*struct_gpiod_chip_info) [*c]const u8;
pub extern fn gpiod_chip_info_get_num_lines(info: ?*struct_gpiod_chip_info) usize;
pub const GPIOD_LINE_VALUE_ERROR: c_int = -1;
pub const GPIOD_LINE_VALUE_INACTIVE: c_int = 0;
pub const GPIOD_LINE_VALUE_ACTIVE: c_int = 1;
pub const enum_gpiod_line_value = c_int;
pub const GPIOD_LINE_DIRECTION_AS_IS: c_int = 1;
pub const GPIOD_LINE_DIRECTION_INPUT: c_int = 2;
pub const GPIOD_LINE_DIRECTION_OUTPUT: c_int = 3;
pub const enum_gpiod_line_direction = c_uint;
pub const GPIOD_LINE_EDGE_NONE: c_int = 1;
pub const GPIOD_LINE_EDGE_RISING: c_int = 2;
pub const GPIOD_LINE_EDGE_FALLING: c_int = 3;
pub const GPIOD_LINE_EDGE_BOTH: c_int = 4;
pub const enum_gpiod_line_edge = c_uint;
pub const GPIOD_LINE_BIAS_AS_IS: c_int = 1;
pub const GPIOD_LINE_BIAS_UNKNOWN: c_int = 2;
pub const GPIOD_LINE_BIAS_DISABLED: c_int = 3;
pub const GPIOD_LINE_BIAS_PULL_UP: c_int = 4;
pub const GPIOD_LINE_BIAS_PULL_DOWN: c_int = 5;
pub const enum_gpiod_line_bias = c_uint;
pub const GPIOD_LINE_DRIVE_PUSH_PULL: c_int = 1;
pub const GPIOD_LINE_DRIVE_OPEN_DRAIN: c_int = 2;
pub const GPIOD_LINE_DRIVE_OPEN_SOURCE: c_int = 3;
pub const enum_gpiod_line_drive = c_uint;
pub const GPIOD_LINE_CLOCK_MONOTONIC: c_int = 1;
pub const GPIOD_LINE_CLOCK_REALTIME: c_int = 2;
pub const GPIOD_LINE_CLOCK_HTE: c_int = 3;
pub const enum_gpiod_line_clock = c_uint;
pub extern fn gpiod_line_info_free(info: ?*struct_gpiod_line_info) void;
pub extern fn gpiod_line_info_copy(info: ?*struct_gpiod_line_info) ?*struct_gpiod_line_info;
pub extern fn gpiod_line_info_get_offset(info: ?*struct_gpiod_line_info) c_uint;
pub extern fn gpiod_line_info_get_name(info: ?*struct_gpiod_line_info) [*c]const u8;
pub extern fn gpiod_line_info_is_used(info: ?*struct_gpiod_line_info) bool;
pub extern fn gpiod_line_info_get_consumer(info: ?*struct_gpiod_line_info) [*c]const u8;
pub extern fn gpiod_line_info_get_direction(info: ?*struct_gpiod_line_info) enum_gpiod_line_direction;
pub extern fn gpiod_line_info_get_edge_detection(info: ?*struct_gpiod_line_info) enum_gpiod_line_edge;
pub extern fn gpiod_line_info_get_bias(info: ?*struct_gpiod_line_info) enum_gpiod_line_bias;
pub extern fn gpiod_line_info_get_drive(info: ?*struct_gpiod_line_info) enum_gpiod_line_drive;
pub extern fn gpiod_line_info_is_active_low(info: ?*struct_gpiod_line_info) bool;
pub extern fn gpiod_line_info_is_debounced(info: ?*struct_gpiod_line_info) bool;
pub extern fn gpiod_line_info_get_debounce_period_us(info: ?*struct_gpiod_line_info) c_ulong;
pub extern fn gpiod_line_info_get_event_clock(info: ?*struct_gpiod_line_info) enum_gpiod_line_clock;
pub const GPIOD_INFO_EVENT_LINE_REQUESTED: c_int = 1;
pub const GPIOD_INFO_EVENT_LINE_RELEASED: c_int = 2;
pub const GPIOD_INFO_EVENT_LINE_CONFIG_CHANGED: c_int = 3;
pub const enum_gpiod_info_event_type = c_uint;
pub extern fn gpiod_info_event_free(event: ?*struct_gpiod_info_event) void;
pub extern fn gpiod_info_event_get_event_type(event: ?*struct_gpiod_info_event) enum_gpiod_info_event_type;
pub extern fn gpiod_info_event_get_timestamp_ns(event: ?*struct_gpiod_info_event) u64;
pub extern fn gpiod_info_event_get_line_info(event: ?*struct_gpiod_info_event) ?*struct_gpiod_line_info;
pub extern fn gpiod_line_settings_new() ?*struct_gpiod_line_settings;
pub extern fn gpiod_line_settings_free(settings: ?*struct_gpiod_line_settings) void;
pub extern fn gpiod_line_settings_reset(settings: ?*struct_gpiod_line_settings) void;
pub extern fn gpiod_line_settings_copy(settings: ?*struct_gpiod_line_settings) ?*struct_gpiod_line_settings;
pub extern fn gpiod_line_settings_set_direction(settings: ?*struct_gpiod_line_settings, direction: enum_gpiod_line_direction) c_int;
pub extern fn gpiod_line_settings_get_direction(settings: ?*struct_gpiod_line_settings) enum_gpiod_line_direction;
pub extern fn gpiod_line_settings_set_edge_detection(settings: ?*struct_gpiod_line_settings, edge: enum_gpiod_line_edge) c_int;
pub extern fn gpiod_line_settings_get_edge_detection(settings: ?*struct_gpiod_line_settings) enum_gpiod_line_edge;
pub extern fn gpiod_line_settings_set_bias(settings: ?*struct_gpiod_line_settings, bias: enum_gpiod_line_bias) c_int;
pub extern fn gpiod_line_settings_get_bias(settings: ?*struct_gpiod_line_settings) enum_gpiod_line_bias;
pub extern fn gpiod_line_settings_set_drive(settings: ?*struct_gpiod_line_settings, drive: enum_gpiod_line_drive) c_int;
pub extern fn gpiod_line_settings_get_drive(settings: ?*struct_gpiod_line_settings) enum_gpiod_line_drive;
pub extern fn gpiod_line_settings_set_active_low(settings: ?*struct_gpiod_line_settings, active_low: bool) void;
pub extern fn gpiod_line_settings_get_active_low(settings: ?*struct_gpiod_line_settings) bool;
pub extern fn gpiod_line_settings_set_debounce_period_us(settings: ?*struct_gpiod_line_settings, period: c_ulong) void;
pub extern fn gpiod_line_settings_get_debounce_period_us(settings: ?*struct_gpiod_line_settings) c_ulong;
pub extern fn gpiod_line_settings_set_event_clock(settings: ?*struct_gpiod_line_settings, event_clock: enum_gpiod_line_clock) c_int;
pub extern fn gpiod_line_settings_get_event_clock(settings: ?*struct_gpiod_line_settings) enum_gpiod_line_clock;
pub extern fn gpiod_line_settings_set_output_value(settings: ?*struct_gpiod_line_settings, value: enum_gpiod_line_value) c_int;
pub extern fn gpiod_line_settings_get_output_value(settings: ?*struct_gpiod_line_settings) enum_gpiod_line_value;
pub extern fn gpiod_line_config_new() ?*struct_gpiod_line_config;
pub extern fn gpiod_line_config_free(config: ?*struct_gpiod_line_config) void;
pub extern fn gpiod_line_config_reset(config: ?*struct_gpiod_line_config) void;
pub extern fn gpiod_line_config_add_line_settings(config: ?*struct_gpiod_line_config, offsets: [*c]const c_uint, num_offsets: usize, settings: ?*struct_gpiod_line_settings) c_int;
pub extern fn gpiod_line_config_get_line_settings(config: ?*struct_gpiod_line_config, offset: c_uint) ?*struct_gpiod_line_settings;
pub extern fn gpiod_line_config_set_output_values(config: ?*struct_gpiod_line_config, values: [*c]const enum_gpiod_line_value, num_values: usize) c_int;
pub extern fn gpiod_line_config_get_num_configured_offsets(config: ?*struct_gpiod_line_config) usize;
pub extern fn gpiod_line_config_get_configured_offsets(config: ?*struct_gpiod_line_config, offsets: [*c]c_uint, max_offsets: usize) usize;
pub extern fn gpiod_request_config_new() ?*struct_gpiod_request_config;
pub extern fn gpiod_request_config_free(config: ?*struct_gpiod_request_config) void;
pub extern fn gpiod_request_config_set_consumer(config: ?*struct_gpiod_request_config, consumer: [*c]const u8) void;
pub extern fn gpiod_request_config_get_consumer(config: ?*struct_gpiod_request_config) [*c]const u8;
pub extern fn gpiod_request_config_set_event_buffer_size(config: ?*struct_gpiod_request_config, event_buffer_size: usize) void;
pub extern fn gpiod_request_config_get_event_buffer_size(config: ?*struct_gpiod_request_config) usize;
pub extern fn gpiod_line_request_release(request: ?*struct_gpiod_line_request) void;
pub extern fn gpiod_line_request_get_chip_name(request: ?*struct_gpiod_line_request) [*c]const u8;
pub extern fn gpiod_line_request_get_num_requested_lines(request: ?*struct_gpiod_line_request) usize;
pub extern fn gpiod_line_request_get_requested_offsets(request: ?*struct_gpiod_line_request, offsets: [*c]c_uint, max_offsets: usize) usize;
pub extern fn gpiod_line_request_get_value(request: ?*struct_gpiod_line_request, offset: c_uint) enum_gpiod_line_value;
pub extern fn gpiod_line_request_get_values_subset(request: ?*struct_gpiod_line_request, num_values: usize, offsets: [*c]const c_uint, values: [*c]enum_gpiod_line_value) c_int;
pub extern fn gpiod_line_request_get_values(request: ?*struct_gpiod_line_request, values: [*c]enum_gpiod_line_value) c_int;
pub extern fn gpiod_line_request_set_value(request: ?*struct_gpiod_line_request, offset: c_uint, value: enum_gpiod_line_value) c_int;
pub extern fn gpiod_line_request_set_values_subset(request: ?*struct_gpiod_line_request, num_values: usize, offsets: [*c]const c_uint, values: [*c]const enum_gpiod_line_value) c_int;
pub extern fn gpiod_line_request_set_values(request: ?*struct_gpiod_line_request, values: [*c]const enum_gpiod_line_value) c_int;
pub extern fn gpiod_line_request_reconfigure_lines(request: ?*struct_gpiod_line_request, config: ?*struct_gpiod_line_config) c_int;
pub extern fn gpiod_line_request_get_fd(request: ?*struct_gpiod_line_request) c_int;
pub extern fn gpiod_line_request_wait_edge_events(request: ?*struct_gpiod_line_request, timeout_ns: i64) c_int;
pub extern fn gpiod_line_request_read_edge_events(request: ?*struct_gpiod_line_request, buffer: ?*struct_gpiod_edge_event_buffer, max_events: usize) c_int;
pub const GPIOD_EDGE_EVENT_RISING_EDGE: c_int = 1;
pub const GPIOD_EDGE_EVENT_FALLING_EDGE: c_int = 2;
pub const enum_gpiod_edge_event_type = c_uint;
pub extern fn gpiod_edge_event_free(event: ?*struct_gpiod_edge_event) void;
pub extern fn gpiod_edge_event_copy(event: ?*struct_gpiod_edge_event) ?*struct_gpiod_edge_event;
pub extern fn gpiod_edge_event_get_event_type(event: ?*struct_gpiod_edge_event) enum_gpiod_edge_event_type;
pub extern fn gpiod_edge_event_get_timestamp_ns(event: ?*struct_gpiod_edge_event) u64;
pub extern fn gpiod_edge_event_get_line_offset(event: ?*struct_gpiod_edge_event) c_uint;
pub extern fn gpiod_edge_event_get_global_seqno(event: ?*struct_gpiod_edge_event) c_ulong;
pub extern fn gpiod_edge_event_get_line_seqno(event: ?*struct_gpiod_edge_event) c_ulong;
pub extern fn gpiod_edge_event_buffer_new(capacity: usize) ?*struct_gpiod_edge_event_buffer;
pub extern fn gpiod_edge_event_buffer_get_capacity(buffer: ?*struct_gpiod_edge_event_buffer) usize;
pub extern fn gpiod_edge_event_buffer_free(buffer: ?*struct_gpiod_edge_event_buffer) void;
pub extern fn gpiod_edge_event_buffer_get_event(buffer: ?*struct_gpiod_edge_event_buffer, index: c_ulong) ?*struct_gpiod_edge_event;
pub extern fn gpiod_edge_event_buffer_get_num_events(buffer: ?*struct_gpiod_edge_event_buffer) usize;
pub extern fn gpiod_is_gpiochip_device(path: [*c]const u8) bool;
pub extern fn gpiod_api_version() [*c]const u8;


// TODO: use these
pub const GpiodLineDirection = enum(c_int) {
    AS_IS = 1,
    INPUT = 2,
    OUTPUT = 3,
};

pub const GpiodLineBias = enum(c_int) {
    AS_IS = 1,
    DISABLED = 2,
    PULL_UP = 3,
    PULL_DOWN = 4,
};

pub const GpiodLineDrive = enum(c_int) {
    PUSH_PULL = 1,
    OPEN_DRAIN = 2,
    OPEN_SOURCE = 3,
};

pub const GpiodLineValue = enum(c_int) {
    INACTIVE = 0,
    ACTIVE = 1,
};

pub const GpiodLineClock = enum(c_int) {
    MONOTONIC = 0,
    REALTIME = 1,
};

// Event types for ctxless
pub const GpiodLineEdge = enum(c_int) {
    EDGE_NONE = 1,
    EDGE_RISING = 2,
    EDGE_FALLING = 3,
    EDGE_BOTH = 4,
};

