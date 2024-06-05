const std = @import("std");

const arraylist = @import("arraylist.zig").ArrayList;
const ArrayList = arraylist.ArrayList;

const zstring = @import("zig-string");
const String = zstring.String;

const Table = struct {
    const This = @This();

    const Data = u64;
    const Xlabel = String;
    const Ylabel = String;

    const Ymap = std.ArrayHashMap(String, usize, zstring.HashContext, 50);
    const Xmap = std.ArrayHashMap(String, Ymap, zstring.HashContext, 50);

    alloc: std.mem.Allocator,
    x: Xmap,
    y: Ymap,
    d: ArrayList(Data),

    pub fn init(comptime alloc: std.mem.Allocator) This {
        return .{
            .alloc = alloc,
            .x = Xmap.init(alloc),
            .y = ArrayList(Ylabel).init(alloc),
            .d = ArrayList(Data).init(alloc),
        };
    }

    pub fn add(this: *This, x: Xlabel, y: Ylabel, d: Data) !bool {
        const hasx = this.xlabels.contains(x, String.eql);
        const hasy = this.xlabels.contains(y, String.eql);
        try this.dates.append(d);
        errdefer _ = this.dates.pop();

        if (!hasx)
            try this.xlabels.append(x);
        errdefer {
            if (!hasx) this.xlabels.pop();
        }

        if (!hasy) try this.ylabels.append(y);
    }
};
