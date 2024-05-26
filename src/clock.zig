const std = @import("std");
const sys = std.os.linux;

const tsc = @import("tsc.zig");
const cal = @import("date.zig");

pub const TimeUnit = enum(u16) {
    nanosec = 0,
    microsec,
    millisec,
    second,
    minute,
    hour,
    day,
    week,
    year,
};

// needed to prevent compiler crash (no idea why this works)
// on version 0.13.0-dev.28+3c5e84073

const time_ratios: [9]u64 = .{
    1,
    1000,
    1000 * 1000,
    1000 * 1000 * 1000,
    1000 * 1000 * 1000 * 60,
    1000 * 1000 * 1000 * 60 * 60,
    1000 * 1000 * 1000 * 60 * 60 * 24,
    1000 * 1000 * 1000 * 60 * 60 * 24 * 7,
    1000 * 1000 * 1000 * 60 * 60 * 24 * 365,
};

pub fn per(comptime x: TimeUnit, comptime y: TimeUnit) u64 {
    return time_ratios[@intFromEnum(y)] / time_ratios[@intFromEnum(x)];
}

/// Any clockid from gettimeofday can be be used and any three
/// of the rdtsc clocks from the rdt file can be used. They are
///   -1) CLOCK_TSC - calls RDTSC
///   -2) CLOCK_TSCP - calls RDTSCP
///   -3) CLOCK_TSCPF -calls RDTSCP then FENCE
/// RDTSCP includes a partial fence in front of it to prevent
/// it from being hoisted ahead of other ops. It was created to help
/// time things. It will also return the core number
/// the read happens on. Something you will also need a fence after
/// it to prevent other ops from being pulled in front of it.
pub fn Clock(comptime clkid: i32) type {
    return struct {
        const This = @This();
        const Moment_type = Moment(This);
        const MomentDiff_type = MomentDiff(This);

        const clockid: i32 = clkid;
        /// zero ticks_per_second implies no relation to wall clock time.
        /// FIXME terrible way to represent this because those clocks still
        /// tick at a constant rate, use epoch instead
        /// TODO put epoch here
        var ticks_per_second: u64 = b: {
            if (clkid >= 0)
                break :b per(.nanosec, .second);
            break :b @intFromFloat(tsc.calibrate_freq(50));
        };

        last: Moment_type,

        pub inline fn get_ticks() !u64 {
            switch (comptime clockid) {
                tsc.CLOCK_TSC => return tsc.rdtsc(),
                tsc.CLOCK_TSCP => return tsc.rdtscp(),
                tsc.CLOCK_TSCPF => return tsc.rdtscp_fenced(),
                else => return get_clock(clockid),
            }
        }

        pub fn init() !This {
            return This{ .last = try now_static() };
        }

        pub fn now_static() !Moment_type {
            return Moment_type.now();
        }

        /// force a read of the clock
        pub fn now(s: *This) !Moment_type {
            const n: Moment_type = try Moment_type.now();
            s.*.last = n;
            return n;
        }

        /// useful for when the most up to date isn't needed and you can
        /// be assured you have read recently, such as in a hot loop around
        /// tasks that are shirt you can afford not to have most up to date.
        pub fn was(s: This) Moment_type {
            return s.was;
        }
    };
}

pub fn Moment(comptime clk: type) type {
    return struct {
        pub const This = @This();
        pub const Diff_type = Clock_type.MomentDiff_type;
        pub const Clock_type = clk;

        tick: u64,

        pub fn now() !This {
            return This{ .tick = try Clock_type.get_ticks() };
        }

        pub fn since(s: This, prev: This) Diff_type {
            return .{ .diff = @intCast(s.tick - prev.tick) };
        }

        pub fn until(s: This, then: This) Diff_type {
            return .{ .diff = @intCast(then.tick - s.tick) };
        }

        pub fn add(s: This, Diff: Diff_type) This {
            return .{ .tick = @intCast(s.tick + Diff.diff) };
        }

        pub fn sub(s: This, Diff: Diff_type) This {
            return .{ .tick = @intCast(s.tick - Diff.diff) };
        }

        pub fn to_day_number(s: This) u32 {
            return @mod(s.tick, per(.nanosec, .day));
        }
    };
}

pub fn MomentDiff(comptime clk: type) type {
    return struct {
        pub const This = @This();
        pub const clock = clk;
        diff: i64,
    };
}

/// Read clock_gettime(2) for a description of all the clocks.
pub const AccurateClock = Clock(sys.CLOCK.REALTIME);
pub const FastClock = Clock(sys.CLOCK.REALTIME_COURSE);
pub const TaiClock = Clock(sys.CLOCK.TAI);

/// These two are not wall clocks as you cannot tell the time from
/// them but they give the most accurate results for short timing intervals
pub const IncSleepTimer = Clock(sys.CLOCK.BOOTTIME);
pub const FastTimer = Clock(sys.CLOCK.MONOTONIC);

pub fn get_clock(clkid: i32) !u64 {
    var ts: sys.timespec = undefined;
    try std.posix.clock_gettime(clkid, &ts);
    return @as(u64, @bitCast(ts.tv_sec)) * per(.nanosec, .second) + @as(u64, @bitCast(ts.tv_nsec));
}

//------ TESTS ------
const TT = std.testing;
test "get_clock" {
    const t = try get_clock(sys.CLOCK.MONOTONIC);
    try TT.expect(t > 0);
}

test "clock" {
    const C = Clock(sys.CLOCK.MONOTONIC);
    var c = try C.init();
    const l = c.last;
    const n = try c.now();
    try TT.expect(l.tick > 0);
    try TT.expect(n.tick > 0);
}
