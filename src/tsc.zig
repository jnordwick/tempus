const std = @import("std");
const clock = @import("clock.zig");

pub const CLOCK_TSC: i32 = -1;
pub const CLOCK_TSCP: i32 = -2;
pub const CLOCK_TSCPF: i32 = -3;

pub const tsc_tps = struct {
    var val: f64 = std.math.nan();
};

pub inline fn rdtscp_fenced() u64 {
    var hi: u32 = 0;
    var low: u32 = 0;
    const clob: u32 = undefined;

    asm (
        \\rdtscp
        \\mfence
        : [low] "={eax}" (low),
          [hi] "={edx}" (hi),
        : [clob] "={ecx}" (clob),
    );
    return (@as(u64, hi) << 32) | @as(u64, low);
}

pub inline fn rdtscp() u64 {
    var hi: u32 = undefined;
    var low: u32 = undefined;
    const clob: u32 = undefined;

    asm (
        \\rdtscp
        : [low] "={eax}" (low),
          [hi] "={edx}" (hi),
        : [clob] "={ecx}" (clob),
    );
    return (@as(u64, hi) << 32) | @as(u64, low);
}

pub inline fn rdtsc() u64 {
    var hi: u32 = 0;
    var low: u32 = 0;

    asm (
        \\rdtsc
        : [low] "={eax}" (low),
          [hi] "={edx}" (hi),
    );
    return (@as(u64, hi) << 32) | @as(u64, low);
}

/// returns time stamp counter ticks per second
/// millis: the length of time to run the frequency calibration. 0 will
/// use a default value
pub fn calibrate_freq(millis: u64) !f64 {
    const nanos_in_mills = 1000 * 1000;
    const CLK = std.os.linux.CLOCK.MONOTONIC;
    const n: u64 = @max(millis, 50);

    const start_wall: u64 = try clock.get_clock(CLK);
    const start_tick: u64 = rdtscp_fenced();
    var end_wall: u64 = start_wall + n * nanos_in_mills;
    var end_tick: u64 = rdtscp_fenced();

    while ((clock.get_clock(CLK) catch unreachable) < end_wall) {}

    end_wall = clock.get_clock(CLK) catch unreachable;
    end_tick = rdtscp_fenced();

    const secs: f64 = @as(f64, @floatFromInt(end_wall - start_wall)) / 1e9;
    const ticks: f64 = @floatFromInt(end_tick - start_tick);

    return ticks / secs;
}

pub fn epoch_offset(freq: f64) !i64 {
    const CLK = std.os.linux.CLOCK.TAI;
    const n = 4;

    var rs: [2 * n]u64 = undefined;
    var cs: [2 * n]u64 = undefined;
    inline for (0..n) |i| {
        rs[i] = rdtscp_fenced();
        cs[i] = try clock.get_clock(CLK);
    }
    inline for (n..2 * n) |i| {
        cs[i] = try clock.get_clock(CLK);
        rs[i] = rdtscp_fenced();
    }

    var rsum: f128 = 0.0;
    var csum: f128 = 0.0;
    const denom: f128 = @as(f128, @floatFromInt(n)) * 2.0;
    for (0..2 * n) |i| {
        rsum += @floatFromInt(rs[i]);
        csum += @floatFromInt(cs[i]);
    }

    const ticks_per_ns = freq / 1e9;
    rsum /= ticks_per_ns;

    const fdiff = (csum - rsum) / denom;
    const diff: i64 = @intFromFloat(fdiff);
    return diff;
}

// ------ TESTING ------
const expect = std.testing.expect;
const expectApprox = std.testing.expectApproxEqAbs;

test "calibrate" {
    const fr = try calibrate_freq(50);
    const start_wall = try clock.get_clock(std.os.linux.CLOCK.TAI);
    const start_tsc = rdtscp_fenced();
    std.posix.nanosleep(0, 1000 * 1000);
    const stop_wall = try clock.get_clock(std.os.linux.CLOCK.TAI);
    const stop_tsc = rdtscp_fenced();

    const tot_wall: f64 = @floatFromInt(stop_wall - start_wall);
    const tot_tsc: f64 = @floatFromInt(stop_tsc - start_tsc);
    const guess_tsc: f64 = (fr / 1e9) * tot_wall;
    try expectApprox(guess_tsc, tot_tsc, 0.01 * tot_tsc);
}

test "epoch" {
    const fr = try calibrate_freq(50);
    const off = try epoch_offset(fr);
    std.posix.nanosleep(0, 100 * 1000 * 1000); // 10 ms
    const ticks_per_ns = fr / 1e9;
    const r: f128 = @floatFromInt(rdtscp());
    const rr: i64 = @intFromFloat(r / ticks_per_ns);
    const c: i64 = @intCast(try clock.get_clock(std.os.linux.CLOCK.TAI));
    const new: i64 = @intCast(rr + off);
    const diff = new - c;
    try std.testing.expectApproxEqAbs(0, @as(f64, @floatFromInt(diff)), 10000); // 10 us
}

test "rdtscp" {
    const t1: u64 = rdtscp();
    const t2: u64 = rdtscp();
    const delta: i128 = @as(i128, t2) - @as(i128, t1);

    try expect(t1 > 0);
    try expect(t2 > 0);
    try expect(delta > 0);
}

test "fenced rdtscp" {
    const t1: u64 = rdtscp_fenced();
    const t2: u64 = rdtscp_fenced();
    const delta: i128 = @as(i128, t2) - @as(i128, t1);

    try expect(t1 > 0);
    try expect(t2 > 0);
    try expect(delta > 0);
}

test "rdtsc" {
    const t1: u64 = rdtsc();
    const t2: u64 = rdtsc();
    const delta: i128 = @as(i128, t2) - @as(i128, t1);

    try expect(t1 > 0);
    try expect(t2 > 0);
    try expect(delta > 0);
}
