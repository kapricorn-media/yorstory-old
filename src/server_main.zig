const builtin = @import("builtin");
const std = @import("std");

const app = @import("zigkm-common-app");
const bigdata = app.bigdata;
const http = @import("http-common");
const server = @import("http-server");

// const bigdata = @import("bigdata.zig");
// const m = @import("math.zig");
const portfolio = @import("portfolio.zig");
const server_util = @import("server_util.zig");

const DEBUG = builtin.mode == .Debug;
const WASM_PATH = if (DEBUG) "zig-out/server/main.wasm" else "main.wasm";
// const WASM_PATH_WORKER = if (DEBUG) "zig-out/server/worker.wasm" else "worker.wasm";
const SERVER_IP = "0.0.0.0";

pub usingnamespace @import("zigkm-common-stb").exports; // for stb linking

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

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, bigdataPath: []const u8) !Self
    {
        const cwd = std.fs.cwd();
        const bigdataFile = try cwd.openFile(bigdataPath, .{});
        defer bigdataFile.close();
        const bigdataBytes = try bigdataFile.readToEndAlloc(allocator, 1024 * 1024 * 1024);

        var self = Self {
            .allocator = allocator,
            .bigdata = bigdataBytes,
            .map = std.StringHashMap([]const u8).init(allocator),
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

            if (std.mem.eql(u8, request.uri, "/webgl_png")) {
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
            } else if (std.mem.eql(u8, request.uri, "/main.wasm")) {
                try server.writeFileResponse(writer, WASM_PATH, allocator);
            } else {
                const uri = if (std.mem.eql(u8, request.uri, "/") or isPortfolioUri) "/wasm.html" else request.uri;
                if (DEBUG) {
                    // For faster iteration
                    // TODO this path can change
                    server.serveStatic(writer, uri, "deps/zigkm-common/src/app/static", allocator) catch |err| switch (err) {
                        error.FileNotFound => {
                            try server.serveStatic(writer, uri, "static", allocator);
                        },
                        else => return err,
                    };
                } else {
                    const data = state.map.get(uri) orelse {
                        try server.writeCode(writer, ._404);
                        try server.writeEndHeader(writer);
                        return;
                    };
                    try server.writeCode(writer, ._200);
                    try server.writeContentLength(writer, data.len);
                    if (server.getFileContentType(uri)) |contentType| {
                        try server.writeContentType(writer, contentType);
                    }
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

pub fn main() !void
{

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
        std.log.err("Expected arguments: datafile port [<https-chain-path> <https-key-path>]", .{});
        return error.BadArgs;
    }

    const dataFile = args[1];
    var state = try ServerState.init(allocator, dataFile);
    defer state.deinit();

    const serverArgs = args[2..];
    try server_util.startFromCmdArgs(SERVER_IP, serverArgs, &state, serverCallbackWrapper, allocator);
}
