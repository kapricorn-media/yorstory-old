const builtin = @import("builtin");
const std = @import("std");

const http = @import("http-common");
const server = @import("http-server");

const config = @import("config");

const WASM_PATH = if (config.DEBUG) "zig-out/yorstory.wasm" else "yorstory.wasm";
// const DOMAIN = if (config.DEBUG) "localhost" else "yorstory.com";
const SERVER_IP = "0.0.0.0";

const Portfolio = struct {
    title: []const u8,
    uri: []const u8,
};

const PORTFOLIO_LIST = [_]Portfolio {
    .{
        .title = "Wandering Earth II",
        .uri = "wandering-earth-ii",
    },
    .{
        .title = "HALO",
        .uri = "halo",
    },
    .{
        .title = "Project X",
        .uri = "project-x",
    },
    .{
        .title = "Cerulea",
        .uri = "cerulea",
    },
    .{
        .title = "The Project",
        .uri = "the-project",
    },
    .{
        .title = "Project Y",
        .uri = "project-y",
    },
    .{
        .title = "123456",
        .uri = "123456",
    },
    .{
        .title = "Lorem ipsum",
        .uri = "lorem-ipsum",
    }
};

pub const log_level: std.log.Level = switch (builtin.mode) {
    .Debug => .debug,
    .ReleaseSafe => .info,
    .ReleaseFast => .info,
    .ReleaseSmall => .info,
};

const ServerCallbackError = server.Writer.Error || error {InternalServerError};

const ServerState = struct {
    allocator: std.mem.Allocator,

    port: u16,
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
            for (PORTFOLIO_LIST) |portfolio| {
                if (request.uri.len < 1) {
                    break;
                }
                const trimmedUri = request.uri[1..];
                if (std.mem.eql(u8, trimmedUri, portfolio.uri)) {
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
                try std.json.stringify(PORTFOLIO_LIST, .{}, json.writer());

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
