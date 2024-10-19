const std = @import("std");
const dset = @import("dataset.zig");
const util = @import("util.zig");

const Atomic = std.atomic.Value;
const Thread = std.Thread;
const fmt = std.fmt;
const math = std.math;
const Allocator = std.mem.Allocator;
const page_alloc = std.heap.page_allocator;
const DataSet = dset.DataSet;
const Data = dset.Data;

/// Force value to be calculated. This calls std.mem.doNotOptimizeAway on it, which sends it
/// to an empty volatile asm block. Since asm blocks are black boxes, the compiler must
/// assume the value is used. Inlined to prevent any copies of a potentially large
pub inline fn blackhole(x: anytype) void {
    std.mem.doNotOptimizeAway(x);
}

// inline: prevent any temp copies? must be a pointer
pub inline fn whitehole(x: anytype) @TypeOf(x).child {
    if (@typeInfo(@TypeOf(x)) != .Pointer)
        @compileError("whitehole expects Pointer");
    std.mem.doNotOptimizeAway(x);
    return x.*;
}

// TODO add allocator arguments
pub var znh_alloc = std.heap.GeneralPurposeAllocator(.{});

const Options = packed struct {
    /// try to determine the baseline for the call and subtract it from the runtime
    /// Experimental, not currently working, and not sure if even useful.
    baseline: bool = false,
    /// If args is an array, treat it as a single argument. The usual behavior is to treat
    /// the array as a list of arguments to be iterated over.
    singular: bool = false,
};

// pub noinline fn count_cross(
//     opt: Options,
//     invokes: usize,
//     comptime funcs: anytype,
//     comptime args: anytype,
// ) !DataSet {
//     const Ftype = @typeInfo(@TypeOf(funcs)).Array.child;
//     const farray: [funcs.len]Ftype = funcs;

//     var dataset = DataSet.init(znh_alloc);
//     inline for (0..farray.len) |fi| {
//         const fname = util.get_fname(farray[fi]);
//         inline for (0..args.len) |ai| {
//             const d: Data = count_single(opt, fname, ai, invokes, farray[fi], args[ai]);
//             try dataset.add(d);
//         }
//     }
//     return dataset;
// }

pub noinline fn count_single(
    /// options, passed in from `cross_count`
    comptime opts: Options,
    /// the function name use for output
    fname: []const u8,
    /// the argument name: either a string or
    aname: anytype,
    passes: u64,
    func: anytype,
    arg: anytype,
) Data {
    const parg = whitehole(&arg);

    const Func_Ret = @typeInfo(@TypeOf(func)).Fn.return_type.?;
    var ret: Func_Ret = undefined;

    // baseline calculation (experimental)
    const invokes = passes * if (opts.singular) 1 else parg.len;
    const base = baseline(@TypeOf(func), func, opts, invokes);

    // actual run
    var p = passes;
    const start = now();
    while (p != 0) {
        if (comptime opts.singular) {
            ret = @call(.never_inline, func, .{parg});
        } else {
            for (0..parg.len) |i| {
                ret = @call(.never_inline, func, .{parg[i]});
            }
        }
        p -= 1;
    }
    const stop = now();

    const delta = stop - start;
    return Data.init(fname, aname, invokes, delta, base);
}

// pub noinline fn time_cross(
//     comptime opt: Options,
//     millis: usize,
//     comptime funcs: anytype,
//     comptime args: anytype,
// ) !DataSet {
//     const Ftype = @typeInfo(@TypeOf(funcs)).Array.child;
//     const farray: [funcs.len]Ftype = funcs;

//     var dataset = DataSet.init(znh_alloc);
//     inline for (0..farray.len) |fi| {
//         const fname = util.get_fname(farray[fi]);
//         inline for (0..args.len) |ai| {
//             const d: Data = time_single(opt, fname, ai, millis, farray[fi], args[ai]);
//             try dataset.add(d);
//         }
//     }
//     return dataset;
// }

pub noinline fn time_single(comptime opt: Options, fname: []const u8, aname: anytype, millis: u64, func: anytype, arg: anytype) Data {
    var varg = arg;
    const pvarg: *volatile @TypeOf(varg) = &varg;
    const vvarg = pvarg.*;

    // std.mem.doNotOptimize seems to get optimized away in non-Debug builds
    // and the never_inline function is then elided
    const func_ti = @typeInfo(@TypeOf(func));
    const ret_type = func_ti.Fn.return_type.?;
    var ret: ret_type = undefined;
    const pvret: *volatile ret_type = &ret;

    const run_nanos = 1000000 * @max(millis, 15);

    var invokes: u64 = 0;
    var done: bool = false;
    const vpdone: *volatile bool = &done;
    var start: u64 = 0;
    const vpstart: *volatile u64 = &start;
    var timer = Thread.spawn(.{}, set_bool, .{ vpdone, vpstart, run_nanos }) catch @panic("could not spawn");

    // actual run
    vpstart.* = now();
    while (!vpdone.*) {
        pvret.* = @call(.never_inline, func, vvarg);
        invokes += 1;
    }
    const stop = now();
    timer.join();

    // baseline calculation
    const base = baseline(opt, invokes);
    const delta = stop - start;

    return Data.init(fname, aname, invokes, delta, base);
}

// pub noinline fn run_timed_slice(
//     comptime opt: Options,
//     fname: []const u8,
//     aname: anytype,
//     millis: u64,
//     comptime func: anytype,
//     args: anytype,
// ) Data {
//     const args_type = @TypeOf(args[0]);
//     const aargs: [*]volatile args_type = @ptrCast(args.ptr);
//     const len = args.len;

//     // std.mem.doNotOptimize seems to get optimized away in non-Debug builds
//     // and the never_inline function is then elided
//     const func_ti = @typeInfo(@TypeOf(func));
//     const ret_type = func_ti.Fn.return_type.?;
//     var ret: ret_type = undefined;
//     const pvret: *volatile ret_type = &ret;

//     const run_nanos = 1000000 * @max(millis, 15);

//     var invokes: u64 = 0;
//     var done: bool = false;
//     const vpdone: *volatile bool = &done;
//     var start: u64 = 0;
//     const vpstart: *volatile u64 = &start;
//     var timer = Thread.spawn(.{}, set_bool, .{ vpdone, vpstart, run_nanos }) catch @panic("could not spawn");

//     // actual run
//     vpstart.* = now();
//     while (!vpdone.*) {
//         for (0..len) |i| {
//             pvret.* = @call(.never_inline, func, aargs[i]);
//             invokes += 1;
//         }
//     }
//     const stop = now();
//     timer.join();

//     // baseline calculation
//     const base = baseline(opt, invokes);
//     const delta = stop - start;

//     return Data.init(fname, aname, invokes, delta, base);
// }

// inline should be fine here as can't optimize through the VDSO or syscall
inline fn now() u64 {
    var ts: std.posix.timespec = undefined;
    std.posix.clock_gettime(std.posix.CLOCK.MONOTONIC, &ts) catch @panic("clock_gettime failed");
    return nanos_from_timespec(ts);
}

fn nanos_from_timespec(ts: std.posix.timespec) u64 {
    const nanos_per_second: u64 = 1000 * 1000 * 1000;
    return @as(u64, @bitCast(ts.tv_sec)) * nanos_per_second + @as(u64, @bitCast(ts.tv_nsec));
}

// too much casting in zig
inline fn toDouble(i: anytype) f64 {
    return @as(f64, @floatFromInt(i));
}

noinline fn baseline(Func: type, func: Func, comptime opt: Options, x: u64) u64 {
    _ = func;
    if (!opt.has(.Baseline)) {
        return 0;
    }

    //var bret = x;
    //const pvbret: *volatile u64 = &bret;

    var i = x;
    const start: u64 = now();
    while (i != 0) {
        pvbret.* = @call(.never_inline, nothing, .{i});
        i -= 1;
    }
    const stop = now();
    if (stop < start) {
        @panic("baseline clock went backwards");
    }
    return stop - start;
}

noinline fn nothing(x: anytype) @TypeOf(x) {
    return x;
}

fn set_bool(flag: *Atomic(bool), start: *Atomic(u64), nanos: u64) void {
    while (start.load(.acquire) == 0) {}
    const cend: u64 = start.load(.acquire) + nanos;
    while (now() < cend) {}
    flag.* = true;
}

//noinline fn arg_slice(s: []u8, t: []u8) u64 {
//    return @intCast(s[0] + t[0]);
//}

//noinline fn arg_ptr(s: *u8, sn: usize, t: *u8, tn: usize) u64 {
//    const r: u64 = @intCast(whitehole(s) + whitehole(t));
//    blackhole(r);
//    return r;
//}

noinline fn bitcount_bk(x: u64) u32 {
    var t: u32 = 0;
    var v = x;
    while (v != 0) {
        t += 1;
        v &= v - 1;
    }
    return t;
}

noinline fn bitcount_pc(x: u64) u32 {
    return @popCount(x);
}

fn tester64(x: f64, y: f64) f64 {
    return @sqrt(x) + @sqrt(y);
}

fn tester32(x: f32, y: f32) f32 {
    return @sqrt(x) + @sqrt(y);
}

fn tester64m(x: f64, y: f64) f64 {
    return std.math.sqrt(x) + std.math.sqrt(y);
}

fn tester32m(x: f32, y: f32) f32 {
    return std.math.sqrt(x) + std.math.sqrt(y);
}

fn testervoid(x: u64) void {
    blackhole(x);
}

// -- == === Testing === == --

const TT = std.testing;
const twriter = std.io.getStdErr().writer();

test "timer thread" {
    const millis100 = 100 * 1000 * 1000;
    var flag: bool = false;
    const vpf: *volatile bool = &flag;
    var start: u64 = 0;
    const vpstart: *volatile u64 = &start;
    var timer = Thread.spawn(.{}, set_bool, .{ vpf, vpstart, millis100 }) catch @panic("could not spawn");
    vpstart.* = now();
    while (!vpf.*) {}
    const stop = now();
    timer.join();

    const tot: f64 = toDouble(stop - start) / 1e6;
    try TT.expectApproxEqAbs(@as(f64, 100.0), tot, 5.0);
}

// test "count single" {
//     const arg_type32 = std.meta.Tuple(&.{ f32, f32 });
//     const arg_type64 = std.meta.Tuple(&.{ f64, f64 });
//     const args32: arg_type32 = .{ 4.0, 9.0 };
//     const args64: arg_type64 = .{ 4.0, 9.0 };

//     var ds = DataSet.init(null);
//     try ds.add(count_single(.None, "tester32", "(a32)", 10000, tester32, args32));
//     try ds.add(count_single(.None, "tester64", "(a64)", 10000, tester64, args64));
//     try ds.add(count_single(.None, "tester32m", "(a32)", 10000, tester32m, args32));
//     try ds.add(count_single(.None, "tester64m", "(a64)", 10000, tester64m, args64));
//     try ds.write(twriter);
// }

// test "cross count single" {
//     const ds = try cross_count_single(
//         .None,
//         null,
//         10000,
//         [_](fn (u64) u32){ bitcount_bk, bitcount_pc },
//         [_]u64{ 123, 456, 789 },
//     );
//     try ds.write(twriter);
// }

// test "count slice" {
//     const arg_type32 = std.meta.Tuple(&.{ f32, f32 });
//     const arg_type64 = std.meta.Tuple(&.{ f64, f64 });
//     var args32 = [_]arg_type32{ .{ 4.0, 9.0 }, .{ 9.0, 4.0 } };
//     var args64 = [_]arg_type64{ .{ 4.0, 9.0 }, .{ 9.0, 4.0 } };

//     var ds = DataSet.init(null);
//     try ds.add(run_count_slice(.Baseline, "stester32", "(a32)", 10000, tester32, &args32));
//     try ds.add(run_count_slice(.Baseline, "stester64", "(a64)", 10000, tester64, &args64));
//     try ds.add(run_count_slice(.Baseline, "stester32m", "(a32)", 10000, tester32m, &args32));
//     try ds.add(run_count_slice(.None, "stester64m", "(a64)", 10000, tester64m, &args64));
//     try ds.write(twriter);
// }

// test "timed single" {
//     const arg_type32 = std.meta.Tuple(&.{ f32, f32 });
//     const arg_type64 = std.meta.Tuple(&.{ f64, f64 });
//     const args32: arg_type32 = .{ 4.0, 9.0 };
//     const args64: arg_type64 = .{ 4.0, 9.0 };

//     var ds = DataSet.init(null);
//     try ds.add(run_timed_single(.Baseline, "tester32", 32, 100, tester32, args32));
//     try ds.add(run_timed_single(.Baseline, "tester64", 64, 100, tester64, args64));
//     try ds.add(run_timed_single(.Baseline, "tester32m", 32, 100, tester32m, args32));
//     try ds.add(run_timed_single(.Baseline, "tester64m", 64, 100, tester64m, args64));
//     try ds.write(twriter);
// }

// test "timed slice" {
//     const arg_type32 = std.meta.Tuple(&.{ f32, f32 });
//     const arg_type64 = std.meta.Tuple(&.{ f64, f64 });
//     var args32 = [_]arg_type32{ .{ 4.0, 9.0 }, .{ 9.0, 4.0 } };
//     var args64 = [_]arg_type64{ .{ 4.0, 9.0 }, .{ 9.0, 4.0 } };

//     var ds = DataSet.init(null);
//     try ds.add(run_timed_slice(.Baseline, "stester32", 32, 100, tester32, &args32));
//     try ds.add(run_timed_slice(.Baseline, "stester64", 64, 100, tester64, &args64));
//     try ds.add(run_timed_slice(.Baseline, "stester32m", 32, 100, tester32m, &args32));
//     try ds.add(run_timed_slice(.Baseline, "stester64m", 64, 100, tester64m, &args64));
//     try ds.write(twriter);
// }

// test "void return" {
//     const arg_type = std.meta.Tuple(&.{u64});
//     var arg = [_]arg_type{ .{now()}, .{now()}, .{now()} };

//     var ds = DataSet.init(null);
//     try ds.add(run_count_single(.None, "void", "(tuple)", 1000000, testervoid, .{now()}));
//     try ds.add(run_count_slice(.None, "svoid", "(ptr)", 1000000, testervoid, &arg));
//     try ds.write(twriter);
// }

// test util.get_fname {
//     const j = WhoAreYou(get_fname).who;
//     const k = HiMyNameIs(get_fname).shady;
//     const l = WhoAreYou(fet_gname).who;
//     const m = HiMyNameIs(fet_gname).shady;
//     std.debug.print("\n{s}\n", .{j});
//     std.debug.print("\n{s}\n", .{k});
//     std.debug.print("\n{s}\n", .{l});
//     std.debug.print("\n{s}\n", .{m});
//     try TT.expectEqualStrings("get_fname", j);
//     try TT.expectEqualStrings("get_fname", k);
//     try TT.expectEqualStrings("get_fname", l);
//     try TT.expectEqualStrings("get_fname", m);
// }
