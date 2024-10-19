const std = @import("std");

//const arraylist = @import("arraylist.zig").ArrayList;
//const ArrayList = arraylist.ArrayList;

const zstring = @import("zig-string");
const String = zstring.String;

const Data = struct {
    v: u64,

    pub fn merge(this: *Data, other: *const Data) void {
        this.x += other.x;
    }
};

const Table = struct {
    const This = @This();

    const StringSet = std.ArrayHashMap(String, void, String.HashContext, false);

    alloc: std.mem.Allocator,

    xset: StringSet,
    yset: StringSet,
    data: ArrayList(ArrayList(Data)),

    pub fn init(comptime alloc: std.mem.Allocator) This {
        return .{
            .alloc = alloc,
            .xset = StringSet.init(alloc),
            .yset = StringSet.init(alloc),
            .data = ArrayList(?Data).init(alloc),
        };
    }

    pub fn add(this: *This, x: String, y: String, d: Data) !void {
        if (!this.xset.contains(x.String.eql)) {
            try this.xset.append(x);
            const row = ArrayList.init(this.alloc, this.yset.length());
            try row.append_fill(this.alloc, .{null}, this.yset.length());
        }
        if (!this.yset.contains(y, String.eql)) {
            try this.yset.append(y);
            for (this.data.items()) |e| {
                try e.append(this.alloc, null);
            }
        }

        const cell = this.data.ref(x).items().ref(y);
        if (cell == null) cell.* = d else cell.merge(d);
    }

    pub fn ref(this: *This, x: String, y: String) ?*Data {
        const r = this.xset.index_of_fn(x, String.eql) orelse return null;
        const c = this.yset.index_of_fn(y, String.eql) orelse return null;
        return this.data.ref(r).ref(c);
    }
};

const TT = std.testing;

test "init" {
    const al = TT.allocator;
    var t = Table.init(al);
    try t.addS(String.init_copy(al, "aaa"), String.init_copy(al, "bbb"), .{ .x = 1 });
}
