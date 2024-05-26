const std = @import("std");

const date = @import("date.zig");

const per = @import("clock.zig").per;
const TU = @import("clock.zig").TimeUnit;

const Timestamp = struct {
    const This = @This();
    const format = "yyyy-MM-ddThh:mm:ss.nnnnnnnnn";

    nanos: u64,
    next_day: u64 = undefined,

    tempore: u64 = undefined,
    last_tempore: u64,

    rata_die: i32 = undefined,
    date: date.Date = undefined,

    text: [format.len]u8 = undefined,

    pub fn init(nanos: u64) This {
        var t: This = .{ .nanos = nanos, .last_tempore = 0 };
        t.recalc();
        return t;
    }

    fn update(this: *This, nanos: u64) void {
        this.nanos = nanos;
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
        this.text[10] = 'T';
        this.full_time();
    }

    fn full_date(this: *This) void {
        const y = this.date._year;
        const m = this.date._month;
        const d = this.date._day;

        write_int(this.text[0..4], @intCast(y));
        this.text[4] = '-';
        write_int(this.text[5..7], m);
        this.text[7] = '-';
        write_int(this.text[8..10], d);
    }

    fn partial_time(this: *This) void {
        const diff = this.tempore - this.last_tempore;
        var t = this.tempore;
        std.debug.print("\n{}\n", .{diff});

        const nanos_in_hour = per(.nanosec, .hour);
        const nanos_in_minute = per(.nanosec, .minute);
        const nanos_in_second = per(.nanosec, .second);
        const secs_in_minute = per(.second, .minute);
        const mins_in_hour = per(.minute, .hour);

        // zig fmt: off
        if (diff < nanos_in_second) {
            const n: u32 = @intCast(t % nanos_in_second);
            write_int(this.text[20..29], n);
        }
        else if (diff < nanos_in_minute) {
            const n: u32 = @intCast(t % nanos_in_second);
            t = t / nanos_in_second;
            write_int(this.text[20..29], n);
            this.text[19] = '.';

            const s: u32 = @intCast(t % secs_in_minute);
            t = t / secs_in_minute;
            write_int(this.text[17..19], s);
            this.text[16] = ':';
        }
        else if (diff < nanos_in_hour) {
            const n: u32 = @intCast(t % nanos_in_second);
            t = t / nanos_in_second;
            write_int(this.text[20..29], n);
            this.text[19] = '.';

            const s: u32 = @intCast(t % secs_in_minute);
            t = t / secs_in_minute;
            write_int(this.text[17..19], s);
            this.text[16] = ':';

            const m: u32 = @intCast(t % mins_in_hour);
            t = t / mins_in_hour;
            write_int(this.text[14..16], m);
            this.text[13] = ':';
        }
        else {
            this.full_time();
        }
    }

    fn full_time(this: *This) void {
        const nanos_in_second = per(.nanosec, .second);
        const secs_in_minute = per(.second, .minute);
        const mins_in_hour = per(.minute, .hour);

        var t = this.tempore;

        const n: u32 = @intCast(t % nanos_in_second);
        t = t / nanos_in_second;
        write_int(this.text[20..29], n);
        this.text[19] = '.';

        const s: u32 = @intCast(t % secs_in_minute);
        t = t / secs_in_minute;
        write_int(this.text[17..19], s);
        this.text[16] = ':';

        const m: u32 = @intCast(t % mins_in_hour);
        t = t / mins_in_hour;
        write_int(this.text[14..16], m);
        this.text[13] = ':';

        const h: u32 = @intCast(t);
        write_int(this.text[11..13], h);

        this.last_tempore = this.tempore;
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

test "write" {
    var s = 1716753307 * per(.nanosec, .second) + 989767545;
    const ans1 = "2024-05-26T19:55:07.989767545";
    const ans2 = "2024-05-26T19:56:10.999777555";
    var t = Timestamp.init(s);
    t.recalc();
    try TT.expectEqualSlices(u8, ans1, &t.text);

    s += per(.nanosec, .minute) + 3 * per(.nanosec, .second) + 10010010;
    t.update(s);
    try TT.expectEqualSlices(u8, ans2, &t.text);
}
