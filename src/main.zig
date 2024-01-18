const std = @import("std");

pub const Data = struct {
    /// name for display purposes
    name: []const u8,
    /// total invocations
    i: u64,
    /// total nanoseconds
    nanos: u64,
    /// mean (nanos / i)
    mean: f64,

    // zig fmt: off
    // keeps on wanting to mash each print call on one long line
    /// calls std.debug.print and displays in a tabular format
    /// .header: print newline and then header lines first
    pub fn dprint(s: @This(), header: bool) void {
        if (header) {
            std.debug.print("\n{s: <10} | {s: >12} | {s: >13} | {s: >6}\n",
                            .{ "name", "invocations", "nanos", "ns/inv" });
            std.debug.print("{s:-<11}|{s:->14}|{s:->15}|{s:->8}\n",
                            .{ "-", "-", "-", "-" });
        }
        std.debug.print("{s: <10} | {d: >12} | {d: >10} ns | {d: >6.2}\n",
                        .{ s.name, s.i, s.nanos, s.mean });
    }
};

/// bench a function wiht a single arguments a set number of times
/// .name: purely for documentation purposes
/// .invokes: number of times to execute
/// .func: the function to call
/// .args: a tuple of the arguments
pub noinline fn run_single(name: []const u8,
                           invokes: u64,
                           func: anytype,
                           arg: anytype) Data {
    var varg = arg;
    var pvarg: *volatile @TypeOf(varg) = &varg;
    var vvarg = pvarg.*;

    // std.mem.doNotOptimize seems to get optimized away in non-Debug builds
    // and the never_inline function is then elided
    const func_ti = @typeInfo(@TypeOf(func));
    const ret_type = func_ti.Fn.return_type.?;
    var ret: ret_type = undefined;
    const pvret: *volatile ret_type = &ret;

    var i = invokes;
    const start: u64 = now();
    while (i != 0) {
        pvret.* = @call(.never_inline, func, vvarg);
        i -= 1;
    }
    const stop = now();

    const delta = stop - start;
    const mean = toDouble(delta) / toDouble(invokes);

    return Data{ .name = name, .i = invokes, .nanos = delta, .mean = mean };
}

/// bench a function against differents arguments a fixed number of times through
/// the entire set. This is useful for functioins who's time can vary for different
/// arguments. Also good for giving the same set of values to diffrent functions.
/// .name: purely for documentation purposes
/// .passes: number of times to loop over the arguments
/// .func: the function to call
/// .args: a slice of tuples of the arguments
pub noinline fn run_slice(name: []const u8, passes: u64, comptime func: anytype, args: anytype) Data {
    const args_type = @TypeOf(args[0]);
    const aargs: [*]volatile args_type = @ptrCast(args.ptr);
    var len = args.len;

    // std.mem.doNotOptimize seems to get optimized away in non-Debug builds
    // and the never_inline function is then elided
    const func_ti = @typeInfo(@TypeOf(func));
    const ret_type = func_ti.Fn.return_type.?;
    var ret: ret_type = undefined;
    const pvret: *volatile ret_type = &ret;

    var p = passes;
    const start: u64 = now();
    while (p != 0) {
        for (0..len) |i| {
            pvret.* = @call(.never_inline, func, aargs[i]);
        }
        p -= 1;
    }
    const stop = now();
    const invokes = len * passes;
    const delta = stop - start;
    const mean = toDouble(delta) / toDouble(invokes);
    return Data{ .name = name, .i = invokes, .nanos = delta, .mean = mean };
}

/// to prevent the compiler from optimizing a result away even in ReleaseFast.
pub inline fn blackhole(x: anytype) void {
    const ret_type = @TypeOf(x);
    var vret: ret_type = undefined;
    const pvret: *volatile ret_type = &vret;
    pvret.* = x;
}

/// To prevent the compiler from optimizing a result away even in ReleaseFast.
/// Sometimes it can be a little easier to use or more efficient if the commpiler
/// insists on recreating the volatile area.
/// .x: A result value to send into a blackhole
/// .y: a pointer to an already existing location to use
pub inline fn blackloc(x: anytype, y: *@TypeOf(x)) void {
    @as(*volatile @TypeOf(x), @ptrCast(y)).* = x;
}


/// To prevent the compiler from optimizing out a read from a location. Casts to
/// volatile and does the read.
/// .X: the type to read
/// .y: the memory location to read from
pub inline fn whiteloc(X: type, y: *X) X {
    return @as(*volatile X, @ptrCast(y)).*;
}

// inline should be fine here as can't optimize through the VDSO or syscall
inline fn now() u64 {
    const nanos_per_second: u64 = 1000 * 1000 * 1000;
    var ts: std.os.timespec = undefined;
    std.os.clock_gettime(std.os.CLOCK.MONOTONIC_RAW, &ts) catch @panic("clock_gettime");
    return @as(u64, @bitCast(ts.tv_sec)) * nanos_per_second + @as(u64, @bitCast(ts.tv_nsec));
}

// too much casing in zig
inline fn toDouble(i: anytype) f64 {
    return @as(f64, @floatFromInt(i));
}

// --- --- TESTING --- ---

pub fn tester64(x: f64, y: f64) f64 {
    return @sqrt(x) + @sqrt(y);
}

pub fn tester32(x: f32, y: f32) f32 {
    return @sqrt(x) + @sqrt(y);
}

pub fn tester64m(x: f64, y: f64) f64 {
    return std.math.sqrt(x) + std.math.sqrt(y);
}

pub fn tester32m(x: f32, y: f32) f32 {
    return std.math.sqrt(x) + std.math.sqrt(y);
}

test "single 10000 invokes" {
    const arg_type32 = std.meta.Tuple(&.{ f32, f32 });
    const arg_type64 = std.meta.Tuple(&.{ f64, f64 });
    var args32: arg_type32 = .{ 4.0, 9.0 };
    var args64: arg_type64 = .{ 4.0, 9.0 };

    run_single("tester32", 10000, tester32, args32).dprint(true);
    run_single("tester64", 10000, tester64, args64).dprint(false);
    run_single("tester32m", 10000, tester32m, args32).dprint(false);
    run_single("tester64m", 10000, tester64m, args64).dprint(false);
}

test "slice 1000 " {
    const arg_type32 = std.meta.Tuple(&.{ f32, f32 });
    const arg_type64 = std.meta.Tuple(&.{ f64, f64 });
    var args32 = [_]arg_type32{ .{ 4.0, 9.0 }, .{ 9.0, 4.0 } };
    var args64 = [_]arg_type64{ .{ 4.0, 9.0 }, .{ 9.0, 4.0 } };

    run_slice("stester32", 10000, tester32, &args32).dprint(true);
    run_slice("stester64", 10000, tester64, &args64).dprint(false);
    run_slice("stester32m", 10000, tester32m, &args32).dprint(false);
    run_slice("stester64m", 10000, tester64m, &args64).dprint(false);
}
