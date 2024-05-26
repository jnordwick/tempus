const std = @import("std");

const Duration = struct {
    nanos: i64,

    pub fn from_nanos(x: i64) Duration {
        return .{ .nanos = x };
    }

    pub fn from_micros(x: i64) Duration {
        return .{ .nanos = x * 1000 };
    }

    pub fn from_millis(x: i64) Duration {
        return .{ .nanos = x * 1000 * 1000 };
    }

    pub fn from_seconds(x: i64) Duration {
        return .{ .nanos = x * 1000 * 1000 * 1000 };
    }

    // inline to elide the struct creation
    pub inline fn to_secns(this: @This()) struct { i64, u32 } {
        const ns_per_sec = 1_000_000_000;
        const s = this.nanos / ns_per_sec;
        const n = this.nanos % ns_per_sec;
        return .{ s, n };
    }
};
