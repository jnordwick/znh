const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.Allocator;

pub const DataSet = struct {
    const This = @This();

    ds: ArrayList(Data),

    pub fn init(alloc: ?Allocator) DataSet {
        return .{ .ds = ArrayList(Data).init(alloc orelse page_alloc) };
    }

    pub fn deinit(this: *This) void {
        this.ds.deinit();
    }

    pub fn add(this: *This, d: Data) !void {
        try this.ds.append(d);
    }

    pub fn write(this: *const This, writer: anytype) !void {
        var len_max: usize = 0;
        var i_max: u64 = 0;
        var gross_max: u64 = 0;
        var base_max: u64 = 0;

        for (this.ds.items) |d| {
            len_max = @max(len_max, d.name_len);
            i_max = @max(i_max, d.i);
            gross_max = @max(gross_max, d.gross);
            base_max = @max(base_max, d.base);
        }

        const name_size = len_max;
        const i_size: u64 = 1 + math.log10(i_max + 1);
        const gross_size: u64 = 1 + math.log10(gross_max + 1);
        const base_size: u64 = 1 + math.log10(base_max + 1);

        _ = try writer.write("\n\n");
        try write_header(writer, name_size, i_size, gross_size, base_size);
        try write_data(writer, this.ds.items, name_size, i_size, gross_size, base_size);
        _ = try writer.write("\n\n");
    }

    fn write_string(writer: anytype, str: []const u8, pad: i32) !void {
        const npad = @max(0, @abs(pad) - str.len);
        if (pad < 0)
            try writer.writeByteNTimes(' ', npad);
        _ = try writer.write(str);
        if (pad > 0)
            try writer.writeByteNTimes(' ', npad);
    }

    fn write_float(writer: anytype, num: f64, pad: i64) !void {
        var buf = [_]u8{0} ** 64;
        const sl = try fmt.format_float.formatFloat(
            &buf,
            num,
            .{ .mode = .decimal, .precision = 2 },
        );

        const space = @as(usize, @intCast(@abs(pad))) - sl.len;
        if (pad < 0 and space > 0)
            try writer.writeByteNTimes(' ', space);

        _ = try writer.write(sl);

        if (pad > 0 and space > 0)
            try writer.writeByteNTimes(' ', space);
    }

    fn write_int(writer: anytype, num: u64, pad: i64) !void {
        var buf = [_]u8{0} ** 32;
        var p: usize = 0;
        var n = num;
        if (n == 0) {
            buf[0] = '0';
            p += 1;
        } else {
            while (n > 0) {
                const c: u8 = @intCast(n % 10);
                buf[p] = '0' + c;
                p += 1;
                n /= 10;
            }
        }

        var beg: usize = 0;
        var end: usize = p - 1;
        while (beg < end) {
            const tmp = buf[beg];
            buf[beg] = buf[end];
            buf[end] = tmp;
            beg += 1;
            end -= 1;
        }

        const space = @as(usize, @intCast(@abs(pad))) - p;
        if (pad < 0 and space > 0)
            try writer.writeByteNTimes(' ', space);

        _ = try writer.write(buf[0..p]);

        if (pad > 0 and space > 0)
            try writer.writeByteNTimes(' ', space);
    }

    fn write_header(writer: anytype, name_: usize, i_: u64, gross_: u64, base_: u64) !void {
        const name: i32 = @intCast(@max(name_, 4));
        const i: i32 = @intCast(@max(i_, 5));
        const gross: i32 = @intCast(@max(gross_, 6));
        const base: i32 = @intCast(@max(base_, 4));

        try write_string(writer, "name", name);
        try writer.writeAll(" │ ");
        try write_string(writer, "invok", -i);
        try writer.writeAll(" │ ");
        try write_string(writer, "gross", -gross);
        try writer.writeAll(" │ ");
        try write_string(writer, "base", -base);
        try writer.writeAll(" │ ");
        try write_string(writer, "net", -gross);
        try writer.writeAll(" │ ");
        try write_string(writer, "ns/inv", -gross);
        try writer.writeByte('\n');

        try writer.writeBytesNTimes("─", @intCast(name));
        try writer.writeAll("─┼─");
        try writer.writeBytesNTimes("─", @intCast(i));
        try writer.writeAll("─┼─");
        try writer.writeBytesNTimes("─", @intCast(gross));
        try writer.writeAll("─┼─");
        try writer.writeBytesNTimes("─", @intCast(base));
        try writer.writeAll("─┼─");
        try writer.writeBytesNTimes("─", @intCast(gross));
        try writer.writeAll("─┼─");
        try writer.writeBytesNTimes("─", @intCast(gross));
        try writer.writeByte('\n');
    }

    fn write_data(writer: anytype, ds: []const Data, name_: usize, i_: u64, gross_: u64, base_: u64) !void {
        const name: i32 = @intCast(@max(name_, 4));
        const i: i32 = @intCast(@max(i_, 5));
        const gross: i64 = @intCast(@max(gross_, 6));
        const base: i64 = @intCast(@max(base_, 4));

        for (ds) |d| {
            const net = d.gross - d.base;
            const fnet: f128 = @floatFromInt(net);
            const finv: f128 = @floatFromInt(d.i);
            const fns: f128 = fnet / finv;
            try write_string(writer, d.name[0..d.name_len], name);
            try writer.writeAll(" │ ");
            try write_int(writer, d.i, -i);
            try writer.writeAll(" │ ");
            try write_int(writer, d.gross, -gross);
            try writer.writeAll(" │ ");
            try write_int(writer, d.base, -base);
            try writer.writeAll(" │ ");
            try write_int(writer, net, -gross);
            try writer.writeAll(" │ ");
            try write_float(writer, @floatCast(fns), -gross);
            try writer.writeByte('\n');
        }
    }
};

pub const Data = struct {
    /// name for display purposes
    name: [100]u8,
    name_len: usize,
    /// total invocations
    i: u64,
    /// total nanoseconds (unadjusted by baseline)
    gross: u64,
    /// baseline nanosecondsd
    base: u64,

    pub fn init(name: []const u8, i: u64, gross: u64, base: u64) Data {
        var d: Data = undefined;
        @memset(&d.name, 0);
        @memcpy(d.name[0..name.len], name);
        d.name_len = name.len;
        d.i = i;
        d.gross = gross;
        d.base = base;
        return d;
    }
};
