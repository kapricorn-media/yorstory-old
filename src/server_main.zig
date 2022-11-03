const builtin = @import("builtin");
const std = @import("std");

const http = @import("http-common");
const server = @import("http-server");
const stb = @cImport({
    @cInclude("stb_image.h");
    @cInclude("stb_image_write.h");
});

const config = @import("config");
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

const ChunkedPngData = struct {
    size: m.Vec2i,
    channels: u8,
    chunkSize: usize,
    chunkData: [][]const u8
};

const ChunkedPngStore = struct {
    allocator: std.mem.Allocator,
    mutex: std.Thread.Mutex,
    map: std.StringHashMap(ChunkedPngData),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self
    {
        return Self {
            .allocator = allocator,
            .mutex = std.Thread.Mutex{},
            .map = std.StringHashMap(ChunkedPngData).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void
    {
        self.map.deinit();
    }

    pub fn get(self: *Self, path: []const u8) ?ChunkedPngData
    {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.map.get(path);
    }

    pub fn put(self: *Self, path: []const u8, data: ChunkedPngData) !void
    {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.map.put(path, data);
    }
};

const ServerState = struct {
    allocator: std.mem.Allocator,

    chunkedPngStore: ChunkedPngStore,
    chunkedPngLoadMutex: std.Thread.Mutex,

    port: u16,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, port: u16) Self
    {
        return Self {
            .allocator = allocator,
            .chunkedPngStore = ChunkedPngStore.init(allocator),
            .chunkedPngLoadMutex = std.Thread.Mutex{},
            .port = port,
        };
    }

    pub fn deinit(self: *Self) void
    {
        self.chunkedPngStore.deinit();
    }
};

fn calculateChunkSize(imageSize: m.Vec2i, chunkSizeMax: usize) usize
{
    if (imageSize.x >= chunkSizeMax) {
        return 0;
    }
    if (imageSize.x * imageSize.y <= chunkSizeMax) {
        return 0;
    }

    const rows = chunkSizeMax / @intCast(usize, imageSize.x);
    return rows * @intCast(usize, imageSize.x);
}

// 8, 4 => 2 | 7, 4 => 2 | 9, 4 => 3
fn integerCeilingDivide(n: usize, s: usize) usize
{
    return ((n + 1) / s) + 1;
}

const StbCallbackData = struct {
    fail: bool,
    writer: std.ArrayList(u8).Writer,
};

fn stbCallback(context: ?*anyopaque, data: ?*anyopaque, size: c_int) callconv(.C) void
{
    const cbData = @ptrCast(*StbCallbackData, @alignCast(@alignOf(*StbCallbackData), context));
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

fn handleWebglPngRequest(state: *ServerState, path: []const u8, chunkSizeMax: usize, writer: server.Writer) !void
{
    var arenaAllocator = std.heap.ArenaAllocator.init(state.allocator);
    defer arenaAllocator.deinit();
    const allocator = arenaAllocator.allocator();

    const data = state.chunkedPngStore.get(path) orelse blk: {
        // mutex here avoids crazy memory usage spikes at the cost of slowness
        state.chunkedPngLoadMutex.lock();
        defer state.chunkedPngLoadMutex.unlock();

        // Read file data
        const fullPath = try std.mem.concat(allocator, u8, &[_][]const u8 {"static", path});
        const cwd = std.fs.cwd();
        // TODO unsafe!!!
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

        // PNG file -> pixel data (stb_image)
        var width: c_int = undefined;
        var height: c_int = undefined;
        var channels: c_int = undefined;
        var d = stb.stbi_load_from_memory(&fileData[0], @intCast(c_int, fileData.len), &width, &height, &channels, 0);
        if (d == null) {
            return error.stbReadFail;
        }
        defer stb.stbi_image_free(d);

        // Start filling out PNG data struct
        const imageSize = m.Vec2i.init(width, height);
        const chunkSize = calculateChunkSize(imageSize, chunkSizeMax);
        const channelsU8 = @intCast(u8, channels);
        const dataSizePixels = @intCast(usize, imageSize.x * imageSize.y);
        const dataSizeBytes = dataSizePixels * channelsU8;
        var pngData = ChunkedPngData{
            .size = imageSize,
            .channels = channelsU8,
            .chunkSize = chunkSize,
            .chunkData = undefined,
        };

        if (chunkSize != 0) {
            // Generate chunked PNG data
            const pixelData = d[0..dataSizeBytes];

            var pngDataBuf = std.ArrayList(u8).init(allocator);
            defer pngDataBuf.deinit();

            const imageSizeXUsize = @intCast(usize, imageSize.x);
            if (chunkSize % imageSizeXUsize != 0) {
                return error.ChunkSizeBadModulo;
            }
            const chunkRows = chunkSize / imageSizeXUsize;
            const n = integerCeilingDivide(dataSizePixels, chunkSize);

            pngData.chunkData = try state.allocator.alloc([]const u8, n);

            var i: usize = 0;
            while (i < n) : (i += 1) {
                const rowStart = chunkRows * i;
                const rowEnd = std.math.min(chunkRows * (i + 1), imageSize.y);
                std.debug.assert(rowEnd > rowStart);
                const rows = rowEnd - rowStart;

                const chunkStart = rowStart * imageSizeXUsize * channelsU8;
                const chunkEnd = rowEnd * imageSizeXUsize * channelsU8;
                const chunkBytes = pixelData[chunkStart..chunkEnd];

                pngDataBuf.clearRetainingCapacity();
                var cbData = StbCallbackData {
                    .fail = false,
                    .writer = pngDataBuf.writer(),
                };
                const pngStride = imageSizeXUsize * channelsU8;
                const writeResult = stb.stbi_write_png_to_func(stbCallback, &cbData, imageSize.x, @intCast(c_int, rows), channels, &chunkBytes[0], @intCast(c_int, pngStride));
                if (writeResult == 0) {
                    return error.stbWriteFail;
                }

                pngData.chunkData[i] = try state.allocator.dupe(u8, pngDataBuf.items);
            }
        }

        const pathDupe = try state.allocator.dupe(u8, path);
        try state.chunkedPngStore.put(pathDupe, pngData);
        break :blk pngData;
    };

    const response = try std.fmt.allocPrint(allocator, "{{\"width\":{},\"height\":{},\"chunkSize\":{}}}", .{data.size.x, data.size.y, data.chunkSize});
    try server.writeCode(writer, ._200);
    try server.writeContentLength(writer, response.len);
    try server.writeContentType(writer, .ApplicationJson);
    try server.writeEndHeader(writer);
    try writer.writeAll(response);
}

fn handleWebglPngTileRequest(state: *ServerState, path: []const u8, index: usize, writer: server.Writer) !void
{
    const data = state.chunkedPngStore.get(path) orelse {
        return error.TileRequestNoPngStore;
    };

    if (data.chunkSize == 0) {
        return error.TileRequestOnUnchunked;
    }
    if (index >= data.chunkData.len) {
        return error.TileIndexOutOfBounds;
    }
    const chunkData = data.chunkData[index];

    try server.writeCode(writer, ._200);
    try server.writeContentLength(writer, chunkData.len);
    try server.writeEndHeader(writer);
    try writer.writeAll(chunkData);
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
                if (request.queryParams.len != 2) {
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
                const chunkSizeMaxP = request.queryParams[1];
                if (!std.mem.eql(u8, chunkSizeMaxP.name, "chunkSizeMax")) {
                    try server.writeCode(writer, ._400);
                    try server.writeEndHeader(writer);
                    return;
                }
                const chunkSizeMax = try std.fmt.parseUnsigned(usize, chunkSizeMaxP.value, 10);

                try handleWebglPngRequest(state, path.value, chunkSizeMax, writer);
                return;
            } else if (std.mem.eql(u8, request.uri, "/webgl_png_chunk")) {
                if (request.queryParams.len != 2) {
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

                const indexP = request.queryParams[1];
                if (!std.mem.eql(u8, indexP.name, "index")) {
                    try server.writeCode(writer, ._400);
                    try server.writeEndHeader(writer);
                    return;
                }
                const index = try std.fmt.parseUnsigned(usize, indexP.value, 10);

                try handleWebglPngTileRequest(state, path.value, index, writer);
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

    var state = ServerState.init(allocator, port);
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
