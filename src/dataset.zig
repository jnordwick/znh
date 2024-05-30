const std = @import("std");
const Allocator = std.mem.Allocator;
const page_alloc = std.heap.page_allocator;
const math = std.math;
const fmt = std.fmt;
const Dir = std.fs.Dir;

const ArrayList = @import("arraylist.zig").ArrayList;

const Context = struct {};

fn data_by_fname(_: Context, x: Data, y: Data) bool {
    return std.mem.order(u8, x.get_fname(), y.get_fname()).compare(.lt);
}

fn data_by_aname(_: Context, x: Data, y: Data) bool {
    return std.mem.order(u8, x.get_aname(), y.get_aname()).compare(.lt);
}

fn string_compare(_: Context, x: []const u8, y: []const u8) bool {
    return std.mem.order(x, y);
}

fn str_equal(x: []const u8, y: []const u8) bool {
    return std.mem.eql(u8, x, y);
}

pub const DataSet = struct {
    const This = @This();

    ds: ArrayList(Data),
    name: []const u8,

    pub fn init(alloc: ?Allocator, name: []const u8) !DataSet {
        return .{
            .ds = try ArrayList(Data).init(alloc orelse page_alloc, null),
            .name = name,
        };
    }

    pub fn deinit(this: *This) void {
        this.ds.deinit();
    }

    pub fn add(this: *This, d: Data) !void {
        try this.ds.append(page_alloc, d);
    }

    fn group(this: *This) !ArrayList([]const u8) {
        std.sort.insertion(Data, this.ds.items(), Context{}, data_by_fname);
        std.sort.insertion(Data, this.ds.items(), Context{}, data_by_aname);
        var funcs = try ArrayList([]const u8).init(page_alloc, null);
        const its = this.ds.items();
        for (0..its.len) |i| {
            if (funcs.index_of_fn(its[i].get_fname(), 0, str_equal) == null)
                try funcs.append(page_alloc, its[i].get_fname());
        }
        return funcs;
    }

    pub fn gnuplot(this: *This, path: []const u8) !void {
        const cwd = std.fs.cwd();
        var d = try cwd.makeOpenPath(path, .{});
        defer d.close();

        var file_buf: [std.fs.MAX_NAME_BYTES]u8 = undefined;
        const file_name = try fmt.bufPrint(&file_buf, "{s}.tsv", .{this.name});
        var file = try d.createFile(file_name, .{ .read = true, .truncate = true });
        var bf = std.io.bufferedWriter(file.writer());
        defer file.close();

        var funcs = try this.group();

        _ = try bf.write("$data << EOD\n");
        _ = try bf.write("ArgSet");
        for (funcs.items()) |func| {
            _ = try bf.write("\t");
            _ = try bf.write(func);
        }
        _ = try bf.write("\n");

        var dpos: usize = 0;
        const its = this.ds.items();
        while (dpos < its.len) {
            var slots = try ArrayList(usize).init(page_alloc, funcs.items().len);
            try slots.append_fill(page_alloc, &.{its.len}, funcs.items().len);
            const arg = its[dpos].get_aname();
            var ipos: usize = dpos;
            while (ipos < its.len) {
                if (!str_equal(arg, its[ipos].get_aname())) {
                    break;
                }
                const f = its[ipos].get_fname();
                const i = funcs.index_of_fn(f, 0, str_equal) orelse @panic("should have been found");
                slots.set(i, ipos);
                ipos += 1;
            }

            _ = try bf.write(arg);
            for (slots.items()) |s| {
                if (s == its.len) {
                    _ = try bf.write("\t-");
                    continue;
                }
                var buf = [_]u8{0} ** 512;
                const sbuf = try std.fmt.bufPrint(&buf, "{d:.2}", .{its[s].get_nsinv()});
                _ = try bf.write("\t");
                _ = try bf.write(sbuf);
            }
            _ = try bf.write("\n");

            dpos = ipos;
        }

        var buf = [_]u8{0} ** 512;
        _ = try bf.write("EOD\n\n");
        _ = try bf.write("set datafile missing \"-\"\n");
        _ = try bf.write("set terminal png\n");
        _ = try bf.write("set output \"alt.png\"\n");
        _ = try bf.write("set style data histogram\n");
        _ = try bf.write("set style histogram clustered\n");
        _ = try bf.write("set style fill solid border\n");
        const pbuf = try std.fmt.bufPrint(&buf, "plot for [COL=2:{d}:1] \"$data\" using COL:xtic(1) title columnheader\n", .{funcs.len + 1});
        _ = try bf.write(pbuf);

        try bf.flush();
    }

    pub fn write(this: *This, writer: anytype) !void {
        var len_max: usize = 0;
        var i_max: u64 = 0;
        var gross_max: u64 = 0;
        var base_max: u64 = 0;

        for (this.ds.items()) |d| {
            len_max = @max(len_max, d.get_name().len);
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
        try write_data(writer, this.ds.items(), name_size, i_size, gross_size, base_size);
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
            try write_string(writer, d.get_name(), name);
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
    const This = @This();

    /// buffer for name
    namebuf: [100]u8,
    /// lengths of of the
    fname_len: usize,
    /// slice of namebuf that is the argument name only
    aname_len: usize,
    /// total invocations
    i: u64,
    /// total nanoseconds (unadjusted by baseline)
    gross: u64,
    /// baseline nanosecondsd
    base: u64,

    pub fn init(fname: []const u8, aname: anytype, i: u64, gross: u64, base: u64) Data {
        switch (@typeInfo(@TypeOf(aname))) {
            .Int => return init_indexed(fname, aname, i, gross, base),
            else => return init_named(fname, aname, i, gross, base),
        }
        unreachable;
    }

    pub fn init_indexed(fname: []const u8, aindex: u64, i: u64, gross: u64, base: u64) Data {
        var buf = [_]u8{0} ** 32;
        buf[0] = '(';
        const len = std.fmt.formatIntBuf(buf[1..], aindex, 10, .lower, .{});
        buf[len + 1] = ')';
        const aname = buf[0 .. len + 2];
        return init_named(fname, aname, i, gross, base);
    }

    pub fn init_named(fname: []const u8, aname: []const u8, i: u64, gross: u64, base: u64) Data {
        var d: Data = undefined;
        @memset(&d.namebuf, 0);
        @memcpy(d.namebuf[0..fname.len], fname);
        @memcpy(d.namebuf[fname.len .. fname.len + aname.len], aname);
        d.fname_len = fname.len;
        d.aname_len = aname.len;
        d.i = i;
        d.gross = gross;
        d.base = base;
        return d;
    }

    pub fn get_name(this: *const This) []const u8 {
        return this.namebuf[0 .. this.fname_len + this.aname_len];
    }

    pub fn get_fname(this: *const This) []const u8 {
        return this.namebuf[0..this.fname_len];
    }

    pub fn get_aname(this: *const This) []const u8 {
        return this.namebuf[this.fname_len .. this.fname_len + this.aname_len];
    }

    pub fn get_net(this: *const This) u64 {
        return this.gross - this.base;
    }

    pub fn get_nsinv(this: *const This) f64 {
        const n: f128 = @floatFromInt(this.get_net());
        const i: f128 = @floatFromInt(this.i);
        return @floatCast(n / i);
    }
};

// -- == === Testing === == --

const TT = std.testing;
const twriter = std.io.getStdErr().writer();

test {
    var ds = try DataSet.init(null, "functest");
    try ds.add(Data.init_indexed("funcA", 1, 100, 454, 10));
    try ds.add(Data.init_indexed("funcA", 2, 100, 432, 10));
    try ds.add(Data.init_indexed("funcB", 1, 100, 743, 10));
    try ds.add(Data.init_indexed("funcB", 2, 100, 765, 10));
    try ds.write(twriter);
    try ds.gnuplot("./ds-gnuplot");
}

//test {
//    const d = Data.init_named("foo", "123", 123, 456, 10);
//    const e = Data.init_indexed("bar", 456, 123, 456, 10);
//
//    try TT.expectEqualStrings("foo123", d.get_name());
//    try TT.expectEqualStrings("bar(456)", e.get_name());
//}
