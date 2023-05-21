const builtin = @import("builtin");
const std = @import("std");

const app = @import("zigkm-app");
const bigdata = app.bigdata;
const http = @import("zigkm-http-common");
const server = @import("zigkm-http-server");

const portfolio = @import("portfolio.zig");

const DEBUG = builtin.mode == .Debug;
const WASM_PATH = if (DEBUG) "zig-out/server/main.wasm" else "main.wasm";
const SERVER_IP = "0.0.0.0";

pub usingnamespace @import("zigkm-stb").exports; // for stb linking

pub const log_level: std.log.Level = switch (builtin.mode) {
    .Debug => .debug,
    .ReleaseSafe => .info,
    .ReleaseFast => .info,
    .ReleaseSmall => .info,
};

const ServerCallbackError = server.Writer.Error || error {InternalServerError};

fn initBigdata(
    path: []const u8,
    bytes: *[]const u8,
    map: *std.StringHashMap([]const u8),
    allocator: std.mem.Allocator) !void
{
    const cwd = std.fs.cwd();
    const file = try cwd.openFile(path, .{});
    defer file.close();
    bytes.* = try file.readToEndAlloc(allocator, 1024 * 1024 * 1024);
    map.* = std.StringHashMap([]const u8).init(allocator);
    try bigdata.load(bytes.*, map);
}

fn deinitBigdata(bytes: *[]const u8, map: *std.StringHashMap([]const u8), allocator: std.mem.Allocator) void
{
    map.deinit();
    allocator.free(bytes.*);
}

const DynamicData = struct {
    bigdata: []const u8,
    map: std.StringHashMap([]const u8),
    portfolioJson: []const u8,
    portfolio: portfolio.Portfolio,
};

const ServerState = struct {
    allocator: std.mem.Allocator,

    bigdataStatic: []const u8,
    mapStatic: std.StringHashMap([]const u8),
    dynamic: DynamicData,
    dynamicAlpha: DynamicData,

    const Self = @This();

    pub fn init(
        bigdataStaticPath: []const u8,
        bigdataDynamicPath: []const u8,
        portfolioJsonPath: []const u8,
        allocator: std.mem.Allocator) !Self
    {
        var self: Self = .{
            .allocator = allocator,
            .bigdataStatic = undefined,
            .mapStatic = undefined,
            .dynamic = undefined,
            .dynamicAlpha = undefined,
        };

        const cwd = std.fs.cwd();
        const porfolioJsonFile = try cwd.openFile(portfolioJsonPath, .{});
        defer porfolioJsonFile.close();
        self.dynamic.portfolioJson = try porfolioJsonFile.readToEndAlloc(allocator, 1024 * 1024 * 1024);
        self.dynamic.portfolio = try portfolio.Portfolio.init(self.dynamic.portfolioJson, allocator);
        self.dynamicAlpha.portfolioJson = try allocator.dupe(u8, self.dynamic.portfolioJson);
        self.dynamicAlpha.portfolio = try portfolio.Portfolio.init(self.dynamicAlpha.portfolioJson, allocator);

        try initBigdata(bigdataStaticPath, &self.bigdataStatic, &self.mapStatic, allocator);
        try initBigdata(bigdataDynamicPath, &self.dynamic.bigdata, &self.dynamic.map, allocator);
        try initBigdata(bigdataDynamicPath, &self.dynamicAlpha.bigdata, &self.dynamicAlpha.map, allocator);
        return self;
    }

    pub fn deinit(self: *Self) void
    {
        self.dynamic.portfolio.deinit(self.allocator);
        self.allocator.free(self.dynamic.portfolioJson);
        self.dynamicAlpha.portfolio.deinit(self.allocator);
        self.allocator.free(self.dynamicAlpha.portfolioJson);
        deinitBigdata(&self.bigdataStatic, &self.mapStatic, self.allocator);
        deinitBigdata(&self.dynamic.bigdata, &self.dynamic.map, self.allocator);
        deinitBigdata(&self.dynamicAlpha.bigdata, &self.dynamicAlpha.map, self.allocator);
    }
};

fn serverCallback(
    state: *ServerState,
    request: server.Request,
    writer: server.Writer) !void
{
    const host = http.getHeader(request, "Host") orelse return error.NoHost;
    const isAdmin = std.mem.startsWith(u8, host, "admin.");
    const isAlpha = std.mem.startsWith(u8, host, "alpha.");
    if (isAdmin) {
        return error.AdminSiteNotImplemented;
    }
    const dynamicMap = if (isAlpha) &state.dynamicAlpha.map else &state.dynamic.map;
    const portfolioJson = if (isAlpha) state.dynamicAlpha.portfolioJson else state.dynamic.portfolioJson;
    const pf = if (isAlpha) state.dynamicAlpha.portfolio else state.dynamic.portfolio;

    const allocator = state.allocator;

    switch (request.method) {
        .Get => {
            var isPortfolioUri = false;
            for (pf.projects) |project| {
                if (std.mem.eql(u8, request.uri, project.uri)) {
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

                const data = state.mapStatic.get(path.value) orelse blk: {
                    if (dynamicMap.get(path.value)) |d| {
                        break :blk d;
                    }
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
            } else if (std.mem.eql(u8, request.uri, "/portfolio")) {
                try server.writeCode(writer, ._200);
                try server.writeContentLength(writer, portfolioJson.len);
                try server.writeContentType(writer, .ApplicationJson);
                try server.writeEndHeader(writer);
                try writer.writeAll(portfolioJson);
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
                    const data = state.mapStatic.get(uri) orelse {
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
        const code = switch (err) {
            error.FileNotFound => http.Code._404,
            else => http.Code._500,
        };
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
    if (args.len < 5) {
        std.log.err("Expected arguments: <bigdata-static> <bigdata-dynamic> <portfolio-json> <port> [<https-chain-path> <https-key-path>]", .{});
        return error.BadArgs;
    }

    const bigdataStaticPath = args[1];
    const bigdataDynamicPath = args[2];
    const portfolioJsonPath = args[3];
    var state = try ServerState.init(
        bigdataStaticPath, bigdataDynamicPath, portfolioJsonPath, allocator
    );
    defer state.deinit();

    const serverArgs = args[4..];
    try server.startFromCmdArgs(SERVER_IP, serverArgs, &state, serverCallbackWrapper, allocator);
}
