const std = @import("std");

const mem = @import("mem.zig");

const Allocator = std.mem.Allocator;

/// Similar to ArrayList but with other operations. This will likey either be removed or
/// converted to use std.ArrayList soon as the extra code is unnecessary.
pub fn ArrayListEx(Item_: type) type {
    return struct {
        const This = @This();
        const Item = Item_;

        const EqualFn = fn (Item, Item) bool;
        const CompareFn = fn (Item, Item) i32;

        arr: std.ArrayList(Item),

        pub fn init(alloc: Allocator, cap: ?usize) !This {
            const c = cap orelse 8;
            const b: [*]Item = b: {
                if (c == 0) break :b Null;
                const sl = try alloc.alloc(Item, c);
                break :b sl.ptr;
            };
            return .{ .base = b, .len = 0, .cap = c };
        }

        pub fn deinit(this: *This, alloc: Allocator) void {
            alloc.free(this.base[0..this.cap]);
        }

        pub fn items(this: *This) []Item {
            return this.base[0..this.len];
        }

        pub fn contains(this: *const This, x: Item, cmp: EqualFn) bool {
            return this.index_of_fn(x, 0, cmp) != null;
        }

        pub fn clear(this: *This) void {
            this.len = 0;
        }

        pub fn capacity(this: *const This) usize {
            return this.cap;
        }

        pub fn length(this: *const This) usize {
            return this.len;
        }

        pub fn remaining(this: *const This) usize {
            return this.cap - this.len;
        }

        pub fn as_slice(this: *const This) []Item {
            return this.base[0..this.len];
        }

        /// returns a subslice of the array. `end` is exclusive like the slice syntax.
        pub fn as_subslice(this: *const This, start: usize, end: usize) []Item {
            return this.base[start..end];
        }

        /// returns a pointer to the element at the given location. This can then
        /// be assigned to. This is most useful for large Items where a copy
        /// would be prohibitive.
        pub fn ref(this: *This, index: usize) *Item {
            return &this.base[index];
        }

        /// returns the element at the given index. returns by copy.
        pub fn get(this: *const This, index: usize) Item {
            return this.base[index];
        }

        /// set a single idnex to Item.
        pub fn set(this: *This, index: usize, it: Item) void {
            this.base[index] = it;
        }

        /// copy the supplied slice starting at 0 to the array starting at `offset`.
        pub fn set_subslice(this: *This, offset: usize, sl: []const Item) void {
            mem.copy(this.base + offset, sl.ptr, sl.len);
        }

        /// Append a single item
        pub fn append(this: *This, alloc: Allocator, it: Item) !void {
            try this.ensure(alloc, 1);
            this.base[this.len] = it;
            this.len += 1;
        }

        /// Appends `n` items taken circularly from `pat`. Example: if `n` is 3 and `pat` is `"ab"`, `"aba"` is appended.
        pub fn append_fill(
            this: *This,
            alloc: Allocator,
            /// The string to copy from. In the case `pat.len` is `1`, memset is used instead.
            pat: []const Item,
            /// The total appended. The new length will be the previous length plus `n`.
            n: usize,
        ) !void {
            try this.ensure(alloc, n);
            if (pat.len == 1) {
                @memset(this.base[this.len .. this.len + n], pat[0]);
            } else {
                var p: [*]Item = this.base + this.len;
                const end: [*]Item = p + n;
                while (@intFromPtr(p + pat.len) <= @intFromPtr(end)) : (p += pat.len) {
                    mem.copy(Item, p, pat.ptr, pat.len);
                }
                if (p != end) {
                    const diff = (@intFromPtr(end) - @intFromPtr(p)) / @sizeOf(Item);
                    mem.copy(Item, p, pat.ptr, diff);
                }
            }
            this.len += n;
        }

        pub fn index_of(this: *const This, x: Item, start: usize, comptime cmp: ?EqualFn) ?usize {
            if (comptime cmp) |c| {
                const end = this.base + this.len;
                var p = this.base + @min(start, this.len);
                while (p != end) : (p += 1) {
                    if (c(p[0], x))
                        return (@intFromPtr(p) - @intFromPtr(this.base)) / @sizeOf(Item);
                }
                return null;
            } else {
                return std.mem.indexOfScalarPos(Item, this.as_slice(), start, it);
            }
        }

        pub fn index_of_any(this: *const This, its: []const Item, start: usize) ?usize {
            return std.mem.indexOfAnyPos(Item, this.as_slice(), start, its);
        }

        inline fn ensure(this: *This, alloc: Allocator, more: usize) !void {
            if (more > this.remaining())
                try this.grow(alloc, more);
        }

        fn calc_new_cap(cap: usize, over: usize) usize {
            return cap + (cap >> 1) + (cap >> 2) + over;
        }

        noinline fn grow(this: *This, alloc: Allocator, more: usize) !void {
            @setCold(true);
            if (this.cap == 0) {
                const new_cap = calc_new_cap(4, more);
                const sl = try alloc.alloc(Item, new_cap);
                this.base = sl.ptr;
                this.cap = sl.len;
                this.len = 0;
                return;
            }
            const new_cap = calc_new_cap(this.cap, more - this.remaining());
            const resized = alloc.resize(this.base[0..this.cap], new_cap);
            if (resized) {
                this.cap = new_cap;
                return;
            }
            const sl = try alloc.alloc(Item, new_cap);
            mem.copy(Item, sl.ptr, this.base, this.len);
            alloc.free(this.base[0..this.cap]);
            this.base = sl.ptr;
            this.cap = sl.len;
        }
    };
}

const tt = std.testing;

test {
    var ar = try ArrayListEx(u8).init(tt.allocator, 0);
    defer ar.deinit(tt.allocator);

    try tt.expectEqual(ar.capacity(), 0);
    try tt.expectEqual(ar.length(), 0);

    try ar.append(tt.allocator, 'z');
    try tt.expectEqual('z', ar.get(0));
    try tt.expectEqual(ar.capacity(), 8);
    try tt.expectEqual(ar.length(), 1);

    try ar.append_fill(tt.allocator, "abc", 8);
    try tt.expectEqualStrings("zabcabcab", ar.as_slice());
}
