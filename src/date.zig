const std = @import("std");

pub const Month = enum(u16) {
    jan = 1,
    feb,
    mar,
    apr,
    may,
    jun,
    jul,
    aug,
    sep,
    oct,
    nov,
    dec,
};

pub const Weekday = enum(u16) {
    mon = 1,
    tue,
    wed,
    thu,
    fri,
    sat,
    sun,
};

pub const DateError = error{
    bad_year,
    bad_month,
    bad_day,
    bad_rata_die,
};

/// A Date object implementing the Proleptic Gregorian Calendar.
/// All fields are one based and use Jan 1, 1970 as the epoch.
/// This will most likely change in the new future so using the
/// accessors will insulate you from that change.
/// unstable: This is current going though some adjustments to
/// make it perform a litter better with some operations. The
/// basic interface is mostly stable, the layout, cycle offset,
/// and epoc will likely change. Using the methods should insulate
/// you from this. year might go a u32 and offset to allow all calc
/// to be done unsigned. Month change to Mar = 0, Jan = 11, and
/// Feb = 12. day might change to zero based too. The accesors
/// will adjust for all this.
pub const Date = packed struct(u64) {
    _day: u16,
    _month: u16,
    _year: i32,

    /// create a date from year, month, and day components.
    /// yr: 1 = 1AD, 0 = 1BC from from [-32800, 2185466)
    /// mon: 1 = Jan, but this might change in the near futture
    /// dy: 1 = first of the month, but this might change in the near future
    pub fn from_ymd(yr: i32, mon: Month, dy: u16) DateError!Date {
        const Lim = LimitsUnix32;
        if (yr < Lim.year_min or yr > Lim.year_max) return DateError.bad_year;
        if (dy < 1 or dy > 31) return DateError.bad_day;
        return .{ ._day = dy, ._month = @intFromEnum(mon), ._year = yr };
    }

    /// create a date from days since the epoch
    /// rd: days since Jan 1, 1970. From [-752269, 1072989554)
    pub fn from_rata_die(rd: i32) Date {
        return date_from_rd(rd);
    }

    /// get year. 1 = 1AD, 0 = 1BC
    pub fn year(this: Date) i32 {
        return this._year;
    }

    /// get month. 1 = January (might change)
    pub fn month(this: Date) Month {
        return @enumFromInt(this._month);
    }

    /// get day of month. 1 = 1st day
    pub fn day(this: Date) u16 {
        return this._day;
    }

    /// returns the days since the epoch
    pub fn to_rata_die(this: Date) i32 {
        return rd_from_date(this._year, this._month, this._day);
    }

    /// true if this is a leap year
    pub fn is_leap(this: Date) bool {
        return is_leap_year(this._year);
    }

    /// the day of the week, Mon = 1, Sun = 7
    pub fn day_of_week(this: Date) Weekday {
        const rd = this.to_rata_die();
        return day_of_week_from_rd(rd);
    }

    /// Formatter for yyyy-mm-dd format
    pub fn format(s: Date, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        if (s._year < 0) {
            try std.fmt.format(writer, "{d:0>4}-{d:0>2}-{d:0>2}", .{ s._year, s._month, s._day });
        } else {
            const ud: u32 = @intCast(s._year);
            try std.fmt.format(writer, "{d:0>4}-{d:0>2}-{d:0>2}", .{ ud, s._month, s._day });
        }
    }
};

pub const LimitsUnix32 = Limits(i32, unix_compcal_offset, 82);

/// constants for a particular year type, epoch, and cycle offset
pub fn Limits(T: type, epoch: T, cycles: T) type {
    return struct {
        const Uint: type = std.meta.Int(.unsigned, @bitSizeOf(T));
        const max: Uint = std.math.maxInt(Uint);

        const Year: type = T;
        const Day: type = u16;

        const k: T = epoch + days_in_cycle * cycles;
        const l: T = 400 * cycles;

        const rd_min: T = -k;
        const rd_max: T = @divTrunc(max - 3, 4) - k;

        const year_min: Year = -l;
        const year_max: Year = @divTrunc(max, 1461) - l + 1;

        const DateType = Date(Year, Month, Day);

        const date_min: DateType = .{ .day = 1, .month = .mar, .year = year_min };
        const date_max: DateType = .{ .day = 28, .month = .feb, .year = year_max };
    };
}

const days_in_year = 365;
const days_in_leap_year = days_in_year + 1;
const days_in_cent = days_in_year * 76 + days_in_leap_year * 24;
const days_in_leap_cent = days_in_cent + 1;
const days_in_cycle = days_in_cent * 3 + days_in_leap_cent; // 146097

const unix_compcal_offset = 719468; // days [0000-03-01 to 1907-01-01)

const rd_shift_cycles: u32 = 82; // shift by cycles to make all unsigned
const rd_shift_years: u32 = 400 * rd_shift_cycles;
const unix_epoch_shift_days: i32 = unix_compcal_offset + days_in_cycle * rd_shift_cycles;

fn to(T: type, x: anytype) T {
    return @intCast(x);
}

/// Calculate date from rata die
/// rd: days since unix epoch (jan 1, 1970 is 0)
pub fn date_from_rd(rd: i32) Date {
    // shift all to positive
    const adj_rd: u32 = @intCast(rd + unix_epoch_shift_days);

    // year
    const c_num: u32 = 4 * adj_rd + 3;
    const cent: u32 = c_num / days_in_cycle;
    const num2: u32 = c_num % days_in_cycle / 4;
    const N_2: u32 = 4 * num2 + 3;
    const P_2: u64 = to(u64, N_2) * 2939745;
    const Z: u32 = to(u32, P_2 / 4294967296);
    const N_Y: u32 = to(u32, P_2 % 4294967296) / 2939745 / 4;
    const Y: u32 = 100 * cent + Z;

    // day and month
    const N_3: u32 = 2141 * N_Y + 197913;
    const M: u32 = N_3 / 65536;
    const D: u32 = N_3 % 65536 / 2141;

    // unshift
    const J: u32 = @intFromBool(N_Y >= 306);
    const Y_G: i32 = to(i32, Y) - to(i32, rd_shift_years) + to(i32, J);
    const M_G: u32 = if (J == 1) M - 12 else M;
    const D_G: u32 = D + 1;

    return .{ ._day = @truncate(D_G), ._month = @truncate(M_G), ._year = Y_G };
}

pub fn rd_from_date(year: i32, month: u32, day: u32) i32 {

    // convert to computation calendar and make zero based
    const pre_mar: u32 = @intFromBool(month <= 2);
    const Y: u32 = to(u32, year + to(i32, rd_shift_years)) - pre_mar;
    const M: u32 = month + 12 * pre_mar;
    const D: u32 = day - 1;
    const C: u32 = Y / 100;

    // Rata die.
    const y_star: u32 = 1461 * Y / 4 - C + C / 4;
    const m_star: u32 = (979 * M - 2919) / 32;
    const N: u32 = y_star + m_star + D;

    // Rata die shift.
    const rd: i32 = to(i32, N) - unix_epoch_shift_days;

    return rd;
}

pub fn is_leap_year(year: i32) bool {
    const shifted: u32 = to(u32, year + to(i32, rd_shift_years));
    const mask: u32 = if (shifted % 100 == 0) 15 else 3;
    return shifted & mask == 0;
}

pub fn days_in_month(year: i32, month: Month) u32 {
    if (month == .feb) {
        const is_leap = is_leap_year(year);
        return 28 + to(u32, @intFromBool(is_leap));
    }

    const m = @intFromEnum(month);
    return 30 | (m ^ (m >> 3)); // Neri, this is cute af. nice.
}

pub fn day_of_week_from_rd(rd: i32) Weekday {
    const urd: u32 = @intCast(rd + unix_epoch_shift_days);
    const dow = (urd + 2) % 7;
    return @enumFromInt(dow + 1);
}

// --- === TESTING === ---
const TT = std.testing;
test "simple dates" {
    var dd: Date = .{ ._year = 1970, ._month = 1, ._day = 1 };
    var rr: i32 = 0;

    var d = date_from_rd(rr);
    var r = d.to_rata_die();
    try TT.expectEqual(dd, d);
    try TT.expectEqual(rr, r);

    dd = .{ ._year = 2024, ._month = 4, ._day = 25 };
    rr = 19838;

    d = date_from_rd(rr);
    r = d.to_rata_die();
    try TT.expectEqual(dd, d);
    try TT.expectEqual(rr, r);

    dd = .{ ._year = -to(i32, rd_shift_years), ._month = 3, ._day = 1 };
    rr = -unix_epoch_shift_days;

    d = date_from_rd(rr);
    r = d.to_rata_die();
    try TT.expectEqual(dd, d);
    try TT.expectEqual(rr, r);
}

test "is leap" {
    try TT.expectEqual(true, is_leap_year(2000));
    try TT.expectEqual(true, is_leap_year(1600));
    try TT.expectEqual(true, is_leap_year(2400));
    try TT.expectEqual(false, is_leap_year(2100));
    try TT.expectEqual(false, is_leap_year(1500));
    try TT.expectEqual(false, is_leap_year(2500));
    try TT.expectEqual(true, is_leap_year(2004));
    try TT.expectEqual(true, is_leap_year(1996));
}

test "days in month" {
    try TT.expectEqual(29, days_in_month(2000, .feb));
    try TT.expectEqual(28, days_in_month(1999, .feb));
    const days: [12]u32 = .{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    for (1..13) |m| {
        try TT.expectEqual(days[m - 1], days_in_month(2001, @enumFromInt(m)));
    }
}

test "weekday from rd" {
    try TT.expectEqual(Weekday.thu, (try Date.from_ymd(1970, .jan, 1)).day_of_week());
    try TT.expectEqual(Weekday.fri, (try Date.from_ymd(1971, .jan, 1)).day_of_week());
    try TT.expectEqual(Weekday.sat, (try Date.from_ymd(1972, .jan, 1)).day_of_week());
    try TT.expectEqual(Weekday.tue, (try Date.from_ymd(2000, .feb, 29)).day_of_week());
}
