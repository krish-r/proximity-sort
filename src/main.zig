const std = @import("std");

const usage_text =
    \\Usage: proximity-sort [OPTIONS] <PATH>
    \\
    \\Arguments:
    \\  <PATH>  Compute the proximity to this path
    \\
    \\Options:
    \\  -h, --help     Print help
    \\      --print0   Print output delimited by ASCII NUL characters instead of newline characters
    \\  -0, --read0    Read input delimited by ASCII NUL characters instead of newline characters
    \\
;

const Data = struct {
    path: []const u8,
    score: i32,
    index: usize,

    /// compares Data based on the score values - highest score will have high priority.
    /// in case of a tie in the score, compare the index - lowest index will have high priority.
    fn compare(_: void, a: Data, b: Data) std.math.Order {
        const order = std.math.order(a.score, b.score).invert();

        return switch (order) {
            .eq => std.math.order(a.index, b.index),
            else => order,
        };
    }
};

pub fn main() !void {
    var arena_instance = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    const stdin = std.io.getStdIn().reader();
    var stdin_br = std.io.bufferedReader(stdin);
    const stdin_r = stdin_br.reader();

    const stdout = std.io.getStdOut().writer();
    var stdout_bw = std.io.bufferedWriter(stdout);
    const stdout_w = stdout_bw.writer();

    // defaults
    var out_sep: u8 = '\n';
    var in_sep: u8 = '\n';
    var path: ?[]const u8 = null;

    const args = try std.process.argsAlloc(arena);
    defer std.process.argsFree(arena, args);

    // parse command-line args
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            try stdout.writeAll(usage_text);
            return std.process.cleanExit();
        } else if (std.mem.eql(u8, arg, "--print0")) {
            out_sep = 0x00;
        } else if (std.mem.eql(u8, arg, "-0") or std.mem.eql(u8, arg, "--read0")) {
            in_sep = 0x00;
        } else if (!std.mem.startsWith(u8, arg, "-")) {
            path = arg;
        } else {
            std.debug.print("unrecognized argument: '{s}'\n", .{arg});
            std.process.exit(1);
        }
    }

    // print error + help and exit if the path is not provided.
    if (path == null or path.?.len == 0) {
        std.debug.print("<PATH> cannot be empty.\n\n", .{});
        try stdout.writeAll(usage_text);
        std.process.exit(1);
    }

    const stdin_contents = try stdin_r.readAllAlloc(arena, std.math.maxInt(u32));
    defer arena.free(stdin_contents);
    var stdin_it = std.mem.splitScalar(u8, stdin_contents, in_sep);

    var input = std.ArrayList([]const u8).init(arena);
    defer input.deinit();
    while (stdin_it.next()) |item| {
        try input.append(item);
    }

    var sorted = try sort(arena, input, path.?);
    defer sorted.deinit();

    for (sorted.items) |item| {
        try stdout_w.writeAll(item);
        try stdout_w.writeAll(&[_]u8{out_sep});
    }

    try stdout_bw.flush();
}

fn sort(allocator: std.mem.Allocator, input: std.ArrayList([]const u8), path: []const u8) !std.ArrayList([]const u8) {
    const sep = std.fs.path.sep;

    var data = std.PriorityQueue(Data, void, Data.compare).init(allocator, {});
    defer data.deinit();

    for (input.items, 0..) |item, i| {
        // skip empty input
        if (item.len == 0) continue;

        var proximity: i32 = 0;
        var missed = false;

        var input_it = std.mem.tokenizeScalar(u8, item, sep);
        var path_it = std.mem.tokenizeScalar(u8, path, sep);

        // check for root component
        if ((@intFromBool(item[0] == sep) ^ @intFromBool(path[0] == sep)) != 0) {
            missed = true;
            proximity -= 1;
        }

        while (input_it.next()) |input_segment| {
            // skip current dir (".") segment in input
            if (std.mem.eql(u8, input_segment, ".")) continue;

            // if already missed, each additional dir is one further away
            if (missed) {
                proximity -= 1;
                continue;
            }

            // skip current dir (".") segment in path
            if (std.mem.eql(u8, path_it.peek() orelse "", ".")) {
                _ = path_it.next();
            }

            // score positively if input and path segments match
            if (path_it.next()) |path_segment| {
                if (std.mem.eql(u8, path_segment, input_segment)) {
                    proximity += 1;
                    continue;
                } else {
                    missed = true;
                }
            }
            proximity -= 1;
        }

        try data.add(.{
            .path = item,
            .score = proximity,
            .index = i,
        });
    }

    var sorted = try std.ArrayList([]const u8).initCapacity(allocator, data.count());
    while (data.removeOrNull()) |item| {
        try sorted.append(item.path);
    }

    return sorted;
}

test "check sort - 1" {
    const allocator = std.testing.allocator;
    var list = std.ArrayList([]const u8).init(allocator);
    defer list.deinit();

    try list.appendSlice(&[_][]const u8{
        "test.txt",
        "bar/test.txt",
        "bar/main.txt",
        "misc/test.txt",
    });

    var sorted = try sort(allocator, list, "bar/main.txt");
    defer sorted.deinit();

    try std.testing.expectEqual("bar/main.txt", sorted.items[0]);
    try std.testing.expectEqual("bar/test.txt", sorted.items[1]);
}

test "check sort - 2" {
    const allocator = std.testing.allocator;
    var list = std.ArrayList([]const u8).init(allocator);
    defer list.deinit();

    try list.appendSlice(&[_][]const u8{
        "baz/controller/admin.rb",
        "foobar/controller/user.rb",
        "baz/views/admin.rb",
        "foobar/controller/admin.rb",
        "foobar/views/admin.rb",
    });

    var sorted = try sort(allocator, list, "foobar/controller/admin.rb");
    defer sorted.deinit();

    try std.testing.expectEqual("foobar/controller/admin.rb", sorted.items[0]);
    try std.testing.expectEqual("foobar/controller/user.rb", sorted.items[1]);
    try std.testing.expectEqual("foobar/views/admin.rb", sorted.items[2]);
}

test "check if root is closer" {
    const allocator = std.testing.allocator;
    var list = std.ArrayList([]const u8).init(allocator);
    defer list.deinit();

    try list.appendSlice(&[_][]const u8{
        "a/foo.txt",
        "b/foo.txt",
        "foo.txt",
    });

    var sorted = try sort(allocator, list, "a/null.txt");
    defer sorted.deinit();

    try std.testing.expectEqual("a/foo.txt", sorted.items[0]);
    try std.testing.expectEqual("foo.txt", sorted.items[1]);
    try std.testing.expectEqual("b/foo.txt", sorted.items[2]);
}

test "check if sort is stable" {
    const allocator = std.testing.allocator;
    var list = std.ArrayList([]const u8).init(allocator);
    defer list.deinit();

    try list.appendSlice(&[_][]const u8{
        "c.txt",
        "b.txt",
        "a.txt",
    });

    var sorted = try sort(allocator, list, "null.txt");
    defer sorted.deinit();

    try std.testing.expectEqual("c.txt", sorted.items[0]);
    try std.testing.expectEqual("b.txt", sorted.items[1]);
    try std.testing.expectEqual("a.txt", sorted.items[2]);
}

test "check if current dir is ignored" {
    const allocator = std.testing.allocator;
    var list = std.ArrayList([]const u8).init(allocator);
    defer list.deinit();

    try list.appendSlice(&[_][]const u8{
        "./first.txt",
        "././second.txt",
        "third.txt",
    });

    var sorted = try sort(allocator, list, "null.txt");
    defer sorted.deinit();

    try std.testing.expectEqual("./first.txt", sorted.items[0]);
    try std.testing.expectEqual("././second.txt", sorted.items[1]);
    try std.testing.expectEqual("third.txt", sorted.items[2]);
}

test "check if same proximity is sorted" {
    const allocator = std.testing.allocator;
    var list = std.ArrayList([]const u8).init(allocator);
    defer list.deinit();

    try list.appendSlice(&[_][]const u8{
        "b/2.txt",
        "b/1.txt",
        "a/x/2.txt",
        "a/x/1.txt",
        "a/2.txt",
        "a/1.txt",
    });

    var sorted = try sort(allocator, list, "null.txt");
    defer sorted.deinit();

    try std.testing.expectEqual("b/2.txt", sorted.items[0]);
    try std.testing.expectEqual("b/1.txt", sorted.items[1]);
    try std.testing.expectEqual("a/2.txt", sorted.items[2]);
    try std.testing.expectEqual("a/1.txt", sorted.items[3]);
    try std.testing.expectEqual("a/x/2.txt", sorted.items[4]);
    try std.testing.expectEqual("a/x/1.txt", sorted.items[5]);
}

test "check if extra separators in input are ignored" {
    const allocator = std.testing.allocator;
    var list = std.ArrayList([]const u8).init(allocator);
    defer list.deinit();

    try list.appendSlice(&[_][]const u8{
        "test.txt",
        "bar//test.txt",
        "bar//main.txt",
        "misc/test.txt",
    });

    var sorted = try sort(allocator, list, "bar/main.txt");
    defer sorted.deinit();

    try std.testing.expectEqual("bar//main.txt", sorted.items[0]);
    try std.testing.expectEqual("bar//test.txt", sorted.items[1]);
    try std.testing.expectEqual("test.txt", sorted.items[2]);
    try std.testing.expectEqual("misc/test.txt", sorted.items[3]);
}

test "check if extra separators in path are ignored" {
    const allocator = std.testing.allocator;
    var list = std.ArrayList([]const u8).init(allocator);
    defer list.deinit();

    try list.appendSlice(&[_][]const u8{
        "test.txt",
        "bar/test.txt",
        "bar/main.txt",
        "misc/test.txt",
    });

    var sorted = try sort(allocator, list, "bar//main.txt");
    defer sorted.deinit();

    try std.testing.expectEqual("bar/main.txt", sorted.items[0]);
    try std.testing.expectEqual("bar/test.txt", sorted.items[1]);
    try std.testing.expectEqual("test.txt", sorted.items[2]);
    try std.testing.expectEqual("misc/test.txt", sorted.items[3]);
}

test "check if root is considered" {
    const allocator = std.testing.allocator;
    var list = std.ArrayList([]const u8).init(allocator);
    defer list.deinit();

    try list.appendSlice(&[_][]const u8{
        "/tmp/test.txt",
        "tmp/main.txt",
        "bar/test.txt",
        "misc/test.txt",
    });

    var sorted = try sort(allocator, list, "tmp/test.txt");
    defer sorted.deinit();

    try std.testing.expectEqual("tmp/main.txt", sorted.items[0]);
    try std.testing.expectEqual("bar/test.txt", sorted.items[1]);
    try std.testing.expectEqual("misc/test.txt", sorted.items[2]);
    try std.testing.expectEqual("/tmp/test.txt", sorted.items[3]);
}
