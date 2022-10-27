const builtin = @import("builtin");
const std = @import("std");

const http = @import("http-common");
const server = @import("http-server");
const stb = @cImport({
    @cInclude("stb_image.h");
    @cInclude("stb_image_write.h");
});

const config = @import("config");
const portfolio = @import("portfolio.zig");

const WASM_PATH = if (config.DEBUG) "zig-out/yorstory.wasm" else "yorstory.wasm";
// const DOMAIN = if (config.DEBUG) "localhost" else "yorstory.com";
const SERVER_IP = "0.0.0.0";

pub const log_level: std.log.Level = switch (builtin.mode) {
    .Debug => .debug,
    .ReleaseSafe => .info,
    .ReleaseFast => .info,
    .ReleaseSmall => .info,
};

const ServerCallbackError = server.Writer.Error || error {InternalServerError};

const PngData = struct {
    width: u16,
    height: u16,
    channels: u8,
    data: []const u8,
};

const ServerState = struct {
    allocator: std.mem.Allocator,

    mapMutex: std.Thread.Mutex,
    pngMap: std.StringHashMap(PngData),

    port: u16,
};

fn serveWebglPngRequest(state: *ServerState, path: []const u8, writer: server.Writer) !void
{
    var arenaAllocator = std.heap.ArenaAllocator.init(state.allocator);
    defer arenaAllocator.deinit();
    const allocator = arenaAllocator.allocator();

    const fullPath = try std.mem.concat(allocator, u8, &[_][]const u8 {"static", path});
    const cwd = std.fs.cwd();
    const file = cwd.openFile(fullPath, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            try server.writeCode(writer, ._404);
            try server.writeEndHeader(writer);
            return;
        },
        else => return err,
    };
    defer file.close();
    const fileData = try file.readToEndAlloc(allocator, 1024 * 1024 * 1024);

    var width: c_int = undefined;
    var height: c_int = undefined;
    var comp: c_int = undefined;
    if (stb.stbi_info_from_memory(&fileData[0], @intCast(c_int, fileData.len), &width, &height, &comp) == 0) {
        return error.FailedToReadPng;
    }

    const response = try std.fmt.allocPrint(allocator, "{{\"width\":{},\"height\":{}}}", .{width, height});
    try server.writeCode(writer, ._200);
    try server.writeContentLength(writer, response.len);
    try server.writeContentType(writer, .ApplicationJson);
    try server.writeEndHeader(writer);
    try writer.writeAll(response);
}

const CallbackData = struct {
    fail: bool,
    writer: server.Writer,
};

fn stbCallback(context: ?*anyopaque, data: ?*anyopaque, size: c_int) callconv(.C) void
{
    const cbData = @ptrCast(*CallbackData, @alignCast(@alignOf(*CallbackData), context));
    if (cbData.fail) {
        return;
    }

    const dataPtr = data orelse {
        cbData.fail = true;
        return;
    };
    const dataU = @ptrCast([*]u8, dataPtr);
    cbData.writer.writeAll(dataU[0..@intCast(usize, size)]) catch {
        cbData.fail = true;
    };
}

fn serveWebglPngTileRequest(state: *ServerState, path: []const u8, chunkSize: usize, index: usize, writer: server.Writer) !void
{
    var arenaAllocator = std.heap.ArenaAllocator.init(state.allocator);
    defer arenaAllocator.deinit();
    const allocator = arenaAllocator.allocator();

    state.mapMutex.lock();
    defer state.mapMutex.unlock();

    const data = state.pngMap.get(path) orelse blk: {
        const fullPath = try std.mem.concat(allocator, u8, &[_][]const u8 {"static", path});
        const cwd = std.fs.cwd();
        const file = cwd.openFile(fullPath, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                try server.writeCode(writer, ._404);
                try server.writeEndHeader(writer);
                return;
            },
            else => return err,
        };
        defer file.close();
        const fileData = try file.readToEndAlloc(allocator, 1024 * 1024 * 1024);

        var width: c_int = undefined;
        var height: c_int = undefined;
        var channels: c_int = undefined;
        var d = stb.stbi_load_from_memory(&fileData[0], @intCast(c_int, fileData.len), &width, &height, &channels, 0);
        if (d == null) {
            return error.stbReadFail;
        }
        defer stb.stbi_image_free(d);

        const dSize = @intCast(usize, width * height * channels);
        const dataDupe = try state.allocator.dupe(u8, d[0..dSize]);
        errdefer state.allocator.free(dataDupe);

        const pngData = PngData{
            .width = @intCast(u16, width),
            .height = @intCast(u16, height),
            .channels = @intCast(u8, channels),
            .data = dataDupe,
        };

        try state.pngMap.put(try state.allocator.dupe(u8, path), pngData);

        break :blk pngData;
    };

    const sizeBytes = @intCast(usize, data.width) * @intCast(usize, data.height) * @intCast(usize, data.channels);
    const chunkSizeBytes = chunkSize * data.channels;
    const chunkStartByte = index * chunkSize * data.channels;
    const chunkEndByte = std.math.min(chunkStartByte + chunkSizeBytes, sizeBytes);
    const chunk = data.data[chunkStartByte..chunkEndByte];
    // std.log.info("{} to {} (len {}, total size {})", .{chunkStartByte, chunkEndByte, chunk.len, sizeBytes});

    const dummyHeight = chunk.len / data.width / data.channels;
    if (chunk.len != dummyHeight * data.width * data.channels) {
        std.log.info("skipping last", .{});
        return;
    }
    var cbData = CallbackData {
        .fail = false,
        .writer = writer,
    };

    try server.writeCode(writer, ._200);
    try server.writeEndHeader(writer);
    const writeResult = stb.stbi_write_png_to_func(stbCallback, &cbData, data.width, @intCast(c_int, dummyHeight), data.channels, &chunk[0], data.width * data.channels);
    if (writeResult == 0) {
        return error.stbWriteFail;
    }
}

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
            if (std.mem.eql(u8, request.uri, "/") or std.mem.eql(u8, request.uri, "/halo")) {
                try server.writeFileResponse(writer, "static/wasm.html", allocator);
                return;
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
                try serveWebglPngRequest(state, path.value, writer);
                return;
            } else if (std.mem.eql(u8, request.uri, "/webgl_png_chunk")) {
                if (request.queryParams.len != 3) {
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
                const chunkSizeP = request.queryParams[1];
                if (!std.mem.eql(u8, chunkSizeP.name, "chunkSize")) {
                    try server.writeCode(writer, ._400);
                    try server.writeEndHeader(writer);
                    return;
                }
                const chunkSize = try std.fmt.parseUnsigned(usize, chunkSizeP.value, 10);

                const indexP = request.queryParams[2];
                if (!std.mem.eql(u8, indexP.name, "index")) {
                    try server.writeCode(writer, ._400);
                    try server.writeEndHeader(writer);
                    return;
                }
                const index = try std.fmt.parseUnsigned(usize, indexP.value, 10);

                try serveWebglPngTileRequest(state, path.value, chunkSize, index, writer);
                return;
            }

            var isPortfolioUri = false;
            for (portfolio.PORTFOLIO_LIST) |pf| {
                if (request.uri.len < 1) {
                    break;
                }
                const trimmedUri = request.uri[1..];
                if (std.mem.eql(u8, trimmedUri, pf.uri)) {
                    isPortfolioUri = true;
                }
            }

            if (isPortfolioUri) {
                try server.writeFileResponse(writer, "static/entry.html", allocator);
            } else if (std.mem.eql(u8, request.uri, "/yorstory.wasm")) {
                try server.writeFileResponse(writer, WASM_PATH, allocator);
            } else if (std.mem.eql(u8, request.uri, "/portfolio")) {
                var json = std.ArrayList(u8).init(allocator);
                defer json.deinit();
                try std.json.stringify(portfolio.PORTFOLIO_LIST, .{}, json.writer());

                try server.writeCode(writer, ._200);
                try server.writeContentType(writer, .ApplicationJson);
                try server.writeContentLength(writer, json.items.len);
                try server.writeEndHeader(writer);
                try writer.writeAll(json.items);
            } else {
                try server.serveStatic(writer, request.uri, "static", allocator);
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
    if (args.len < 2) {
        std.log.err("Expected arguments: port [<https-chain-path> <https-key-path>]", .{});
        return error.BadArgs;
    }

    const port = try std.fmt.parseUnsigned(u16, args[1], 10);
    const HttpsArgs = struct {
        chainPath: []const u8,
        keyPath: []const u8,
    };
    var httpsArgs: ?HttpsArgs = null;
    if (args.len > 2) {
        if (args.len != 4) {
            std.log.err("Expected arguments: port [<https-chain-path> <https-key-path>]", .{});
            return error.BadArgs;
        }
        httpsArgs = HttpsArgs {
            .chainPath = args[2],
            .keyPath = args[3],
        };
    }

    var state = ServerState {
        .allocator = allocator,
        .mapMutex = std.Thread.Mutex{},
        .pngMap = std.StringHashMap(PngData).init(allocator),
        .port = port,
    };
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
