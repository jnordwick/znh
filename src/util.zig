const std = @import("std");

pub fn move(T: type, dst: [*]T, src: [*]const T, n: usize) void {
    // zig fmt: off
    if (dst < src) std.mem.copyForwards(dst[0..n], src[0..n])
    else if (dst > src) std.mem.copyBackwards(dst[0..n], src[0..n]);
}

pub fn copy(T: type, dst: [*]T, src: [*]const T, n: usize) void {
    @memcpy(dst, src[0..n]);
}

const dno = std.mem.doNotOptimizeAway;

fn WhoAreYou(x: anytype) type {
    return struct {
        const t = x;
        pub const the = @typeName(@This());
        pub const who = the[0 .. the.len - 3][26..];
    };
}

pub fn get_fname(comptime func: anytype) []const u8 {
    return WhoAreYou(func).who;
}
