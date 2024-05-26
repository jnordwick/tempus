const std = @import("std");

pub const Stdev = struct {
    n: u64,
    mean: f64,
    stdev: f64,
};

pub fn mean(samples: []const f64) f64 {
    var sum: f80 = 0.0;
    for (samples) |s| {
        sum += s;
    }
    return @floatCast(sum / @as(f80, @floatFromInt(samples.len)));
}

pub fn stdev(samples: []const f64) Stdev {
    var sqs: f80 = 0.0;
    const avg = mean(samples);
    for (samples) |s| {
        sqs += (s - avg) * (s - avg);
    }
    const sd = @sqrt(sqs / @as(f80, @floatFromInt(samples.len)));
    return .{ .n = samples.len, .mean = @floatCast(avg), .stdev = @floatCast(sd) };
}

// --- --- TEST --- ---
test "stdevit" {
    const s = [_]f64{ 30.0, 43.0, 17.0, 47.0, 60.0 };
    const r = stdev(&s);

    try std.testing.expectEqual(@as(u64, 5), r.n);
    try std.testing.expectApproxEqAbs(@as(f64, 39.4), r.mean, @as(f64, @floatCast(0.1)));
    try std.testing.expectApproxEqAbs(@as(f64, 14.7), r.stdev, @as(f64, @floatCast(0.1)));
}
