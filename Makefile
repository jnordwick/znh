ZIG_FLAGS=--release=safe --verbose

all: build

clean:
	rm -rf .zig-cache zig-out

build: zig-out/bin/zstats

test:
	zig build test ${ZIG_FLAGS}

zig-out/bin/zstats: src/root.zig
	zig build ${ZIG_FLAGS}

