const builtin = @import("builtin");
const std = @import("std");

const http = @import("http-common");
const server = @import("http-server");
const stb = @cImport({
    @cInclude("stb_image.h");
    @cInclude("stb_image_write.h");
});

const config = @import("config");

const bigdata = @import("bigdata.zig");
const m = @import("math.zig");
const portfolio = @import("portfolio.zig");

const WASM_PATH = if (config.DEBUG) "zig-out/yorstory.wasm" else "yorstory.wasm";
const SERVER_IP = "0.0.0.0";

pub const log_level: std.log.Level = switch (builtin.mode) {
    .Debug => .debug,
    .ReleaseSafe => .info,
    .ReleaseFast => .info,
    .ReleaseSmall => .info,
};

const ServerCallbackError = server.Writer.Error || error {InternalServerError};

const ServerState = struct {
    allocator: std.mem.Allocator,

    bigdata: []const u8,
    map: std.StringHashMap([]const u8),

    port: u16,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, port: u16, bigdataPath: []const u8) !Self
    {
        const cwd = std.fs.cwd();
        const bigdataFile = try cwd.openFile(bigdataPath, .{});
        defer bigdataFile.close();
        const bigdataBytes = try bigdataFile.readToEndAlloc(allocator, 1024 * 1024 * 1024);

        var self = Self {
            .allocator = allocator,
            .bigdata = bigdataBytes,
            .map = std.StringHashMap([]const u8).init(allocator),
            .port = port,
        };
        try bigdata.load(bigdataBytes, &self.map);
        return self;
    }

    pub fn deinit(self: *Self) void
    {
        self.allocator.free(self.bigdata);
        self.map.deinit();
    }
};

fn serverCallback(
    state: *ServerState,
    request: server.Request,
    writer: server.Writer) !void
{
    const host = http.getHeader(request, "Host") orelse return error.NoHost;
    _ = host;

    const allocator = state.allocator;

    switch (request.method) {
        .Get => {
            var isPortfolioUri = false;
            for (portfolio.PORTFOLIO_LIST) |pf| {
                if (std.mem.eql(u8, request.uri, pf.uri)) {
                    isPortfolioUri = true;
                }
            }

            if (std.mem.eql(u8, request.uri, "/") or isPortfolioUri) {
                try server.writeFileResponse(writer, "static/wasm.html", allocator);
            } else if (std.mem.eql(u8, request.uri, "/webgl_png")) {
                if (request.queryParams.len != 1) {
                    try server.writeCode(writer, ._400);
                    try server.writeEndHeader(writer);
                    return;
                }

                const path = request.queryParams[0];
                if (!std.mem.eql(u8, path.name, "path")) {
                    try server.writeCode(writer, ._400);
                    try server.writeEndHeader(writer);
                    return;
                }

                const data = state.map.get(path.value) orelse {
                    try server.writeCode(writer, ._404);
                    try server.writeEndHeader(writer);
                    return;
                };
                try server.writeCode(writer, ._200);
                try server.writeContentLength(writer, data.len);
                try server.writeEndHeader(writer);
                try writer.writeAll(data);
            } else if (std.mem.eql(u8, request.uri, "/yorstory.wasm")) {
                try server.writeFileResponse(writer, WASM_PATH, allocator);
            } else {
                if (config.DEBUG) {
                    // For faster iteration
                    try server.serveStatic(writer, request.uri, "static", allocator);
                } else {
                    const data = state.map.get(request.uri) orelse {
                        try server.writeCode(writer, ._404);
                        try server.writeEndHeader(writer);
                        return;
                    };
                    try server.writeCode(writer, ._200);
                    try server.writeContentLength(writer, data.len);
                    try server.writeEndHeader(writer);
                    try writer.writeAll(data);
                }
            }
        },
        .Post => {
            try server.writeCode(writer, ._404);
            try server.writeEndHeader(writer);
        },
    }
}

fn serverCallbackWrapper(
    state: *ServerState,
    request: server.Request,
    writer: server.Writer) ServerCallbackError!void
{
    serverCallback(state, request, writer) catch |err| {
        std.log.err("serverCallback failed, error {}", .{err});
        const code = http.Code._500;
        try server.writeCode(writer, code);
        try server.writeEndHeader(writer);
        return error.InternalServerError;
    };
}

fn httpRedirectCallback(_: void, request: server.Request, writer: server.Writer) !void
{
    // TODO we don't have an allocator... but it's ok, I guess
    var buf: [2048]u8 = undefined;
    const host = http.getHeader(request, "Host") orelse return error.NoHost;
    const redirectUrl = try std.fmt.bufPrint(&buf, "https://{s}{s}", .{host, request.uriFull});

    try server.writeRedirectResponse(writer, redirectUrl);
}

fn httpRedirectEntrypoint(allocator: std.mem.Allocator) !void
{
    var s = try server.Server(void).init(httpRedirectCallback, {}, null, allocator);
    const port = 80;

    std.log.info("Listening on {s}:{} (HTTP -> HTTPS redirect)", .{SERVER_IP, port});
    s.listen(SERVER_IP, port) catch |err| {
        std.log.err("server listen error {}", .{err});
        return err;
    };
    s.stop();
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        if (gpa.deinit()) {
            std.log.err("GPA detected leaks", .{});
        }
    }
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer allocator.free(args);
    if (args.len < 3) {
        std.log.err("Expected arguments: port datafile [<https-chain-path> <https-key-path>]", .{});
        return error.BadArgs;
    }

    const port = try std.fmt.parseUnsigned(u16, args[1], 10);
    const HttpsArgs = struct {
        chainPath: []const u8,
        keyPath: []const u8,
    };
    var httpsArgs: ?HttpsArgs = null;
    if (args.len > 3) {
        if (args.len != 5) {
            std.log.err("Expected arguments: port datafile [<https-chain-path> <https-key-path>]", .{});
            return error.BadArgs;
        }
        httpsArgs = HttpsArgs {
            .chainPath = args[3],
            .keyPath = args[4],
        };
    }

    const dataFile = args[2];
    var state = try ServerState.init(allocator, port, dataFile);
    defer state.deinit();

    var s: server.Server(*ServerState) = undefined;
    var httpRedirectThread: ?std.Thread = undefined;
    {
        if (httpsArgs) |ha| {
            const cwd = std.fs.cwd();
            const chainFile = try cwd.openFile(ha.chainPath, .{});
            defer chainFile.close();
            const chainFileData = try chainFile.readToEndAlloc(allocator, 1024 * 1024 * 1024);
            defer allocator.free(chainFileData);

            const keyFile = try cwd.openFile(ha.keyPath, .{});
            defer keyFile.close();
            const keyFileData = try keyFile.readToEndAlloc(allocator, 1024 * 1024 * 1024);
            defer allocator.free(keyFileData);

            const httpsOptions = server.HttpsOptions {
                .certChainFileData = chainFileData,
                .privateKeyFileData = keyFileData,
            };
            s = try server.Server(*ServerState).init(
                serverCallbackWrapper, &state, httpsOptions, allocator
            );
            httpRedirectThread = try std.Thread.spawn(.{}, httpRedirectEntrypoint, .{allocator});
        } else {
            s = try server.Server(*ServerState).init(
                serverCallbackWrapper, &state, null, allocator
            );
            httpRedirectThread = null;
        }
    }
    defer s.deinit();

    std.log.info("Listening on {s}:{} (HTTPS {})", .{SERVER_IP, port, httpsArgs != null});
    s.listen(SERVER_IP, port) catch |err| {
        std.log.err("server listen error {}", .{err});
        return err;
    };
    s.stop();

    if (httpRedirectThread) |t| {
        t.detach(); // TODO we don't really care for now
    }
}
