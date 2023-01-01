const builtin = @import("builtin");
const std = @import("std");

const http = @import("http-common");
const server = @import("http-server");
const stb = @cImport({
    @cInclude("stb_image.h");
    @cInclude("stb_image_write.h");
});

const png = @import("png");

const config = @import("config");
const m = @import("math.zig");
const portfolio = @import("portfolio.zig");
const psd = @import("psd.zig");

const WASM_PATH = if (config.DEBUG) "zig-out/yorstory.wasm" else "yorstory.wasm";
const SERVER_IP = "0.0.0.0";

const CHUNK_SIZE_MAX = if (config.DEBUG) 1024 * 1024 * 1024 else 512 * 1024;

pub const log_level: std.log.Level = switch (builtin.mode) {
    .Debug => .debug,
    .ReleaseSafe => .info,
    .ReleaseFast => .info,
    .ReleaseSmall => .info,
};

const ServerCallbackError = server.Writer.Error || error {InternalServerError};

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

fn pixelDataToPngChunkedFormat(imageSize: m.Vec2i, channels: u8, pixelData: []const u8, chunkSize: usize, allocator: std.mem.Allocator) ![]const u8
{
    var outBuf = std.ArrayList(u8).init(allocator);
    defer outBuf.deinit();

    const sizeType = u64;
    var widthBytes = try outBuf.addManyAsArray(@sizeOf(sizeType));
    std.mem.writeIntBig(sizeType, widthBytes, @intCast(sizeType, imageSize.x));
    var heightBytes = try outBuf.addManyAsArray(@sizeOf(sizeType));
    std.mem.writeIntBig(sizeType, heightBytes, @intCast(sizeType, imageSize.y));
    var chunkSizeBytes = try outBuf.addManyAsArray(@sizeOf(sizeType));
    std.mem.writeIntBig(sizeType, chunkSizeBytes, chunkSize);

    var pngDataBuf = std.ArrayList(u8).init(allocator);
    defer pngDataBuf.deinit();

    const imageSizeXUsize = @intCast(usize, imageSize.x);
    if (chunkSize % imageSizeXUsize != 0) {
        return error.ChunkSizeBadModulo;
    }
    const chunkRows = if (chunkSize == 0) @intCast(usize, imageSize.y) else chunkSize / imageSizeXUsize;
    const dataSizePixels = @intCast(usize, imageSize.x * imageSize.y);
    const n = if (chunkSize == 0) 1 else integerCeilingDivide(dataSizePixels, chunkSize);

    var numChunksBytes = try outBuf.addManyAsArray(@sizeOf(sizeType));
    std.mem.writeIntBig(sizeType, numChunksBytes, n);

    var i: usize = 0;
    while (i < n) : (i += 1) {
        const rowStart = chunkRows * i;
        const rowEnd = std.math.min(chunkRows * (i + 1), imageSize.y);
        std.debug.assert(rowEnd > rowStart);
        const rows = rowEnd - rowStart;

        const chunkStart = rowStart * imageSizeXUsize * channels;
        const chunkEnd = rowEnd * imageSizeXUsize * channels;
        const chunkBytes = pixelData[chunkStart..chunkEnd];

        pngDataBuf.clearRetainingCapacity();
        var cbData = StbCallbackData {
            .fail = false,
            .writer = pngDataBuf.writer(),
        };
        const pngStride = imageSizeXUsize * channels;
        const writeResult = stb.stbi_write_png_to_func(stbCallback, &cbData, imageSize.x, @intCast(c_int, rows), @intCast(c_int, channels), &chunkBytes[0], @intCast(c_int, pngStride));
        if (writeResult == 0) {
            return error.stbWriteFail;
        }

        var chunkLenBytes = try outBuf.addManyAsArray(@sizeOf(sizeType));
        std.mem.writeIntBig(sizeType, chunkLenBytes, pngDataBuf.items.len);
        try outBuf.appendSlice(pngDataBuf.items);
    }

    return outBuf.toOwnedSlice();
}

fn pngToChunkedFormat(pngData: []const u8, chunkSizeMax: usize, allocator: std.mem.Allocator) ![]const u8
{
    const pngDataLenInt = @intCast(c_int, pngData.len);

    // PNG file -> pixel data (stb_image)
    var width: c_int = undefined;
    var height: c_int = undefined;
    var channels: c_int = undefined;
    var result = stb.stbi_info_from_memory(&pngData[0], pngDataLenInt, &width, &height, &channels);
    if (result != 1) {
        return error.stbiInfoFail;
    }

    const imageSize = m.Vec2i.init(width, height);
    const chunkSize = calculateChunkSize(imageSize, chunkSizeMax);

    if (chunkSize != 0) {
        var d = stb.stbi_load_from_memory(&pngData[0], @intCast(c_int, pngData.len), &width, &height, &channels, 0);
        if (d == null) {
            return error.stbReadFail;
        }
        defer stb.stbi_image_free(d);

        const channelsU8 = @intCast(u8, channels);
        const dataSizePixels = @intCast(usize, imageSize.x * imageSize.y);
        const dataSizeBytes = dataSizePixels * channelsU8;

        const pixelData = d[0..dataSizeBytes];
        return pixelDataToPngChunkedFormat(imageSize, channelsU8, pixelData, chunkSize, allocator);
    } else {
        var outBuf = std.ArrayList(u8).init(allocator);
        defer outBuf.deinit();

        const sizeType = u64;
        var widthBytes = try outBuf.addManyAsArray(@sizeOf(sizeType));
        std.mem.writeIntBig(sizeType, widthBytes, @intCast(sizeType, imageSize.x));
        var heightBytes = try outBuf.addManyAsArray(@sizeOf(sizeType));
        std.mem.writeIntBig(sizeType, heightBytes, @intCast(sizeType, imageSize.y));
        var chunkSizeBytes = try outBuf.addManyAsArray(@sizeOf(sizeType));
        std.mem.writeIntBig(sizeType, chunkSizeBytes, chunkSize);

        var numChunksBytes = try outBuf.addManyAsArray(@sizeOf(sizeType));
        std.mem.writeIntBig(sizeType, numChunksBytes, 1);
        var chunkLenBytes = try outBuf.addManyAsArray(@sizeOf(sizeType));
        std.mem.writeIntBig(sizeType, chunkLenBytes, pngData.len);
        try outBuf.appendSlice(pngData);

        return outBuf.toOwnedSlice();
    }
}

const ChunkedPngStore = struct {
    allocator: std.mem.Allocator,
    map: std.BufMap,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self
    {
        var self = Self {
            .allocator = allocator,
            .map = std.BufMap.init(allocator),
        };
        errdefer self.deinit();
        try self.loadImages();
        return self;
    }

    pub fn deinit(self: *Self) void
    {
        self.map.deinit();
    }

    pub fn loadImages(self: *Self) !void
    {
        const dirPath = "static/images";
        const cwd = std.fs.cwd();
        var dir = try cwd.openDir(dirPath, .{});
        defer dir.close();

        var dirIterable = try cwd.openIterableDir(dirPath, .{});
        defer dirIterable.close();

        var walker = try dirIterable.walk(self.allocator);
        defer walker.deinit();
        while (try walker.next()) |entry| {
            if (entry.kind != .File) {
                continue;
            }

            if (std.mem.endsWith(u8, entry.path, ".png")) {
                // std.log.info("loading {s}", .{entry.path});

                var arenaAllocator = std.heap.ArenaAllocator.init(self.allocator);
                defer arenaAllocator.deinit();
                const allocator = arenaAllocator.allocator();

                // Read file data
                const file = try dir.openFile(entry.path, .{});
                defer file.close();
                const fileData = try file.readToEndAlloc(allocator, 1024 * 1024 * 1024);
                const chunked = try pngToChunkedFormat(fileData, CHUNK_SIZE_MAX, allocator);
                const uri = try std.fmt.allocPrint(allocator, "/images/{s}", .{entry.path});
                try self.map.put(uri, chunked);
                // std.log.info("- done ({}K -> {}K)", .{fileData.len / 1024, chunked.len / 1024});
            } else if (std.mem.endsWith(u8, entry.path, ".psd")) {
                std.log.info("loading {s}", .{entry.path});
                var arenaAllocator = std.heap.ArenaAllocator.init(self.allocator);
                defer arenaAllocator.deinit();
                const allocator = arenaAllocator.allocator();

                // Read file data
                const file = try dir.openFile(entry.path, .{});
                defer file.close();
                const fileData = try file.readToEndAlloc(allocator, 1024 * 1024 * 1024);

                var psdFile: psd.PsdFile = undefined;
                try psdFile.load(fileData, allocator);
                for (psdFile.layers) |l, i| {
                    const dashInd = std.mem.indexOfScalar(u8, l.name, '-') orelse continue;
                    const pre = l.name[0..dashInd];
                    var allNumbers = true;
                    for (pre) |c| {
                        if (!('0' <= c and c <= '9')) {
                            allNumbers = false;
                            break;
                        }
                    }
                    if (!allNumbers) continue;

                    const layerPixelData = try psdFile.getLayerPixelData(i, null, allocator);
                    std.log.info("layer {} - {s}", .{i, l.name});
                    std.log.info("{}", .{layerPixelData.topLeft});
                    std.log.info("{}", .{layerPixelData.size});
                    std.log.info("{}", .{layerPixelData.channels});
                    const chunkSize = calculateChunkSize(layerPixelData.size, CHUNK_SIZE_MAX);
                    const chunked = try pixelDataToPngChunkedFormat(layerPixelData.size, layerPixelData.channels, layerPixelData.data, chunkSize, allocator);
                    const outputDir = entry.path[0..entry.path.len - 4];
                    const uri = try std.fmt.allocPrint(allocator, "/images/{s}/{s}.png", .{outputDir, l.name});
                    try self.map.put(uri, chunked);
                    std.log.info("wrote chunked layer as {s}", .{uri});
                }
            }
        }
    }
};

const ServerState = struct {
    allocator: std.mem.Allocator,

    chunkedPngStore: ChunkedPngStore,

    port: u16,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, port: u16) !Self
    {
        return Self {
            .allocator = allocator,
            .chunkedPngStore = try ChunkedPngStore.init(allocator),
            .port = port,
        };
    }

    pub fn deinit(self: *Self) void
    {
        self.chunkedPngStore.deinit();
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

                const data = state.chunkedPngStore.map.get(path.value) orelse {
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

    var state = try ServerState.init(allocator, port);
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
