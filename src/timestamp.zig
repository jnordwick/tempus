const std = @import("std");

const date = @import("date.zig");

const per = @import("clock.zig").per;
const TU = @import("clock.zig").TimeUnit;

/// A textual timestamp, currently fixed at "yyyy-MM-ddThh:mm:ss.nnnnnnnnn".
/// It does not have it own clock, but takes in a nanosecond value.  On init
/// and update calls it will check to see if it is a different day,  if so it
/// simply do a full recalculation, but if still the same day (the check is
/// just a comparison against a pre calculated next_day value), it will try
/// to only update the parts of the time component it needs to do to cut down
/// on the expensive integer division and modulos. So if you updated in the last
/// second, the call will only update the nanosecond part.
const Timestamp = struct {
    const This = @This();
    const format = "yyyy-MM-ddThh:mm:ss.nnnnnnnnn";

    nanos: u64,
    next_day: u64 = undefined,

    tempore: u64 = undefined,
    last_tempore: u64,

    rata_die: i32 = undefined,
    date: date.Date = undefined,

    text: [format.len]u8 = format.*,

    /// initialize a timestamp with time. text will be valid upon return.
    pub fn init(nanos: u64) This {
        var t: This = .{ .nanos = nanos, .last_tempore = 0 };
        t.recalc();
        return t;
    }

    /// update the timestamp with the new value. This attempts to only
    /// update the fewest parts of the time as long as still the same day.
    pub fn update(this: *This, nanos: u64) void {
        if (nanos >= this.next_day)
            return this.recalc();

        this.tempore = nanos % per(.nanosec, .day);
        this.partial_time();
    }

    fn recalc(this: *This) void {
        const nanos_per_day = per(.nanosec, .day);
        const next_part = (this.nanos + (nanos_per_day - 1)) / nanos_per_day;
        this.next_day = next_part * nanos_per_day;
        this.rata_die = @intCast(this.nanos / nanos_per_day);
        this.tempore = this.nanos % nanos_per_day;
        this.date = date.Date.from_rata_die(this.rata_die);
        this.full_text();
    }

    fn full_text(this: *This) void {
        this.full_date();
        this.full_time();
    }

    fn full_date(this: *This) void {
        const y = this.date._year;
        const m = this.date._month;
        const d = this.date._day;

        write_int(this.text[0..4], @intCast(y));
        write_int(this.text[5..7], m);
        write_int(this.text[8..10], d);
    }

    fn full_time(this: *This) void {
        var t = this.tempore;
        t = update_part(per(.nanosec, .second), t, this.text[20..29]);
        t = update_part(per(.second, .minute), t, this.text[17..19]);
        t = update_part(per(.minute, .hour), t, this.text[14..16]);
        write_int(this.text[11..13], @intCast(t));
        this.last_tempore = this.tempore;
    }

    fn partial_time(this: *This) void {
        const diff = this.tempore - this.last_tempore;
        var t = this.tempore;
        std.debug.print("\n{}\n", .{diff});

        const nanos_in_hour = per(.nanosec, .hour);
        const nanos_in_minute = per(.nanosec, .minute);
        const nanos_in_second = per(.nanosec, .second);

        // zig fmt: off
        if (diff < nanos_in_second) {
            t = update_part(per(.nanosec, .second), t, this.text[20 .. 29]);
        }
        else if (diff < nanos_in_minute) {
            t = update_part(per(.nanosec, .second), t, this.text[20 .. 29]);
            t = update_part(per(.second, .minute), t, this.text[17 .. 19]);
        }
        else if (diff < nanos_in_hour) {
            t = update_part(per(.nanosec, .second), t, this.text[20 .. 29]);
            t = update_part(per(.second, .minute), t, this.text[17 .. 19]);
            t = update_part(per(.minute, .hour), t, this.text[14 .. 16]);
        }
        else {
            this.full_time();
            return;
        }
        this.last_tempore = this.tempore;
    }

    fn update_part(ratio: u64, t: u64, buf: []u8) u64 {
        const m: u32 = @intCast(t % ratio);
        write_int(buf, m);
        return t / ratio;
    }

};

fn write_int(buf: []u8, num: u32) void {
    var pos: i32 = @intCast(buf.len - 1);
    var n = num;

    while (n > 0) : (n = n / 10) {
        const c = '0' + @as(u8, @intCast(n % 10));
        buf[@intCast(pos)] = c;
        pos -= 1;
    }
    if (pos >= 0) {
        while (pos >= 0) : (pos -= 1) {
            buf[@intCast(pos)] = '0';
        }
    }
}

// --- === Testing === ---
const TT = std.testing;

test write_int {
    var b: [4]u8 = undefined;
    write_int(&b, 1234);
    try TT.expectEqualSlices(u8, "1234", &b);
    write_int(&b, 0);
    try TT.expectEqualSlices(u8, "0000", &b);
}

test Timestamp {
    const now = 1716753307 * per(.nanosec, .second) + 989767545;
    const delta = per(.nanosec, .minute) + 3 * per(.nanosec, .second) + 10010010; // 1m 3s 10010010ns
    const later = now + delta;

    const ans_now = "2024-05-26T19:55:07.989767545";
    const ans_later = "2024-05-26T19:56:10.999777555";

    var t = Timestamp.init(now);
    try TT.expectEqualSlices(u8, ans_now, &t.text);

    t.update(later);
    try TT.expectEqualSlices(u8, ans_later, &t.text);
}
