const builtin = @import("builtin");
const std = @import("std");

const http = @import("http-common");
const server = @import("http-server");

const config = @import("config");

const WASM_PATH = if (config.DEBUG) "zig-out/yorstory.wasm" else "yorstory.wasm";
// const DOMAIN = if (config.DEBUG) "localhost" else "yorstory.com";
const SERVER_IP = "0.0.0.0";

const Subproject = struct {
    name: []const u8,
    description: []const u8,
    images: []const []const u8,
};

const Portfolio = struct {
    title: []const u8,
    uri: []const u8,
    // images: []const []const u8,
    cover: []const u8,
    landing: []const u8,
    subprojects: []const Subproject,
};

const PORTFOLIO_LIST = [_]Portfolio {
    .{
        .title = "HALO",
        .uri = "halo",
        //     "images/HALO/bishopbeam/1.png",
        //     "images/HALO/bishopbeam/2.png",
        //     "images/HALO/bishopbeam/3.png",
        //     "images/HALO/bishopbeam/4.png",
        //     "images/HALO/bishopbeam/5.png",
        //     "images/HALO/bishopbeam/6.png",

        //     "",
        //     "",
        //     "",
        //     "",
        //     "",
        //     "",

        //     "images/HALO/Forerunner/1.png",
        //     "images/HALO/Forerunner/2.png",
        //     "images/HALO/Forerunner/3.png",
        //     "images/HALO/Forerunner/4.png",
        //     "images/HALO/Forerunner/5.png",
        //     "images/HALO/Forerunner/6.png",
        //     "images/HALO/Forerunner/7.png",
        //     "images/HALO/Forerunner/8.png",
        //     "images/HALO/Forerunner/9.png",

        //     "",
        //     "",
        //     "",

        //     "",
        //     "",
        //     "",
        //     "",
        //     "",
        //     "",

        //     "images/HALO/Forerunner2/1.png",
        //     "images/HALO/Forerunner2/2.png",
        //     "images/HALO/Forerunner2/3.png",
        //     "images/HALO/Forerunner2/4.png",
        //     "images/HALO/Forerunner2/5.png",
        //     "images/HALO/Forerunner2/6.png",

        //     "",
        //     "",
        //     "",
        //     "",
        //     "",
        //     "",

        //     "images/HALO/GrappleArmor/1.png",
        //     "images/HALO/GrappleArmor/2.png",
        //     "images/HALO/GrappleArmor/3.png",
        //     "images/HALO/GrappleArmor/4.png",
        //     "images/HALO/GrappleArmor/5.png",
        //     "images/HALO/GrappleArmor/6.png",

        //     "",
        //     "",
        //     "",
        //     "",
        //     "",
        //     "",

        //     "images/HALO/GrappleBeam/1.png",
        //     "images/HALO/GrappleBeam/2.png",
        //     "images/HALO/GrappleBeam/3.png",
        //     "images/HALO/GrappleBeam/4.png",
        //     "images/HALO/GrappleBeam/5.png",
        //     "images/HALO/GrappleBeam/6.png",
        //     "images/HALO/GrappleBeam/7.png",
        //     "images/HALO/GrappleBeam/8.png",
        //     "images/HALO/GrappleBeam/9.png",
        //     "images/HALO/GrappleBeam/10.png",
        //     "images/HALO/GrappleBeam/11.png",

        //     "",

        //     "",
        //     "",
        //     "",
        //     "",
        //     "",
        //     "",

        //     "images/HALO/Mortar/1.png",
        //     "images/HALO/Mortar/2.png",
        //     "images/HALO/Mortar/3.png",
        //     "images/HALO/Mortar/4.png",
        //     "images/HALO/Mortar/5.png",
        //     "images/HALO/Mortar/6.png",
        //     "images/HALO/Mortar/7.png",
        //     "images/HALO/Mortar/8.png",

        //     "",
        //     "",
        //     "",
        //     "",

        //     "",
        //     "",
        //     "",
        //     "",
        //     "",
        //     "",

        //     "images/HALO/Pelican/1.png",
        //     "images/HALO/Pelican/2.png",
        //     "images/HALO/Pelican/3.png",
        //     "images/HALO/Pelican/4.png",
        //     "images/HALO/Pelican/5.png",
        //     "images/HALO/Pelican/6.png",
        //     "images/HALO/Pelican/7.png",
        //     "images/HALO/Pelican/8.png",
        //     "images/HALO/Pelican/9.png",
        //     "images/HALO/Pelican/10.png",
        //     "images/HALO/Pelican/11.png",
        // },
        .cover = "images/HALO/attachbeam2/5.png",
        .landing = "images/HALO/landing.png",
        .subprojects = &[_]Subproject {
            .{
                .name = "ATTACH BEAM",
                .description = "By attaching a tether to an opponent, the player is able to deliver a series of devastating pulses to further damage their enemy.",
                .images = &[_][]const u8{
                    "images/HALO/attachbeam1/1.png",
                    "images/HALO/attachbeam1/2.png",
                    "images/HALO/attachbeam1/3.png",
                    "images/HALO/attachbeam1/4.png",
                    "images/HALO/attachbeam1/5.png",
                    "images/HALO/attachbeam1/6.png",
                    "images/HALO/attachbeam1/7.png",
                    "images/HALO/attachbeam1/8.png",
                    "images/HALO/attachbeam1/9.png",
                    "images/HALO/attachbeam1/10.png",
                    "images/HALO/attachbeam1/11.png",
                    "images/HALO/attachbeam1/12.png",
                },
            },
            .{
                .name = "ATTACH BEAM II",
                .description = "Anyone who has played Halo knows that there's a lot of vehicular combat. Using the Attach Beam, a player connects a tether to their opponent's vehicle. Once connected, a player is able to deliver a series of pulses to destroy their enemy's vehicle.",
                .images = &[_][]const u8{
                    "images/HALO/attachbeam2/1.png",
                    "images/HALO/attachbeam2/2.png",
                    "images/HALO/attachbeam2/3.png",
                    "images/HALO/attachbeam2/4.png",
                    "images/HALO/attachbeam2/5.png",
                    "images/HALO/attachbeam2/6.png",
                    "images/HALO/attachbeam2/7.png",
                    "images/HALO/attachbeam2/8.png",
                    "images/HALO/attachbeam2/9.png",
                    "images/HALO/attachbeam2/10.png",
                    "images/HALO/attachbeam2/11.png",
                    "images/HALO/attachbeam2/12.png",
                },
            },
            .{
                .name = "BISHOP BEAM",
                .description = "By attaching a tether to an opponent, the player is able to deliver a series of devastating pulses to further damage their enemy.",
                .images = &[_][]const u8{
                    "images/HALO/bishopbeam/1.png",
                    "images/HALO/bishopbeam/2.png",
                    "images/HALO/bishopbeam/3.png",
                    "images/HALO/bishopbeam/4.png",
                    "images/HALO/bishopbeam/5.png",
                    "images/HALO/bishopbeam/6.png",
                },
            },
            .{
                .name = "FORERUNNER",
                .description = "By attaching a tether to an opponent, the player is able to deliver a series of devastating pulses to further damage their enemy.",
                .images = &[_][]const u8{
                    "images/HALO/Forerunner/1.png",
                    "images/HALO/Forerunner/2.png",
                    "images/HALO/Forerunner/3.png",
                    "images/HALO/Forerunner/4.png",
                    "images/HALO/Forerunner/5.png",
                    "images/HALO/Forerunner/6.png",
                    "images/HALO/Forerunner/7.png",
                    "images/HALO/Forerunner/8.png",
                    "images/HALO/Forerunner/9.png",
                },
            },
            .{
                .name = "FORERUNNER II",
                .description = "By attaching a tether to an opponent, the player is able to deliver a series of devastating pulses to further damage their enemy.",
                .images = &[_][]const u8{
                    "images/HALO/Forerunner2/1.png",
                    "images/HALO/Forerunner2/2.png",
                    "images/HALO/Forerunner2/3.png",
                    "images/HALO/Forerunner2/4.png",
                    "images/HALO/Forerunner2/5.png",
                    "images/HALO/Forerunner2/6.png",
                },
            },
            .{
                .name = "GRAPPLE ARMOR",
                .description = "By attaching a tether to an opponent, the player is able to deliver a series of devastating pulses to further damage their enemy.",
                .images = &[_][]const u8{
                    "images/HALO/GrappleArmor/1.png",
                    "images/HALO/GrappleArmor/2.png",
                    "images/HALO/GrappleArmor/3.png",
                    "images/HALO/GrappleArmor/4.png",
                    "images/HALO/GrappleArmor/5.png",
                    "images/HALO/GrappleArmor/6.png",
                },
            },
            .{
                .name = "GRAPPLE BEAM",
                .description = "By attaching a tether to an opponent, the player is able to deliver a series of devastating pulses to further damage their enemy.",
                .images = &[_][]const u8{
                    "images/HALO/GrappleBeam/1.png",
                    "images/HALO/GrappleBeam/2.png",
                    "images/HALO/GrappleBeam/3.png",
                    "images/HALO/GrappleBeam/4.png",
                    "images/HALO/GrappleBeam/5.png",
                    "images/HALO/GrappleBeam/6.png",
                    "images/HALO/GrappleBeam/7.png",
                    "images/HALO/GrappleBeam/8.png",
                    "images/HALO/GrappleBeam/9.png",
                    "images/HALO/GrappleBeam/10.png",
                    "images/HALO/GrappleBeam/11.png",
                },
            },
            .{
                .name = "MORTAR",
                .description = "By attaching a tether to an opponent, the player is able to deliver a series of devastating pulses to further damage their enemy.",
                .images = &[_][]const u8{
                    "images/HALO/Mortar/1.png",
                    "images/HALO/Mortar/2.png",
                    "images/HALO/Mortar/3.png",
                    "images/HALO/Mortar/4.png",
                    "images/HALO/Mortar/5.png",
                    "images/HALO/Mortar/6.png",
                    "images/HALO/Mortar/7.png",
                    "images/HALO/Mortar/8.png",
                },
            },
            .{
                .name = "PELICAN",
                .description = "By attaching a tether to an opponent, the player is able to deliver a series of devastating pulses to further damage their enemy.",
                .images = &[_][]const u8{
                    "images/HALO/Pelican/1.png",
                    "images/HALO/Pelican/2.png",
                    "images/HALO/Pelican/3.png",
                    "images/HALO/Pelican/4.png",
                    "images/HALO/Pelican/5.png",
                    "images/HALO/Pelican/6.png",
                    "images/HALO/Pelican/7.png",
                    "images/HALO/Pelican/8.png",
                    "images/HALO/Pelican/9.png",
                    "images/HALO/Pelican/10.png",
                    "images/HALO/Pelican/11.png",
                },
            },
        },
    },
    .{
        .title = "Wandering Earth II",
        .uri = "wandering-earth-ii",
        .cover = undefined,
        .landing = undefined,
        .subprojects = undefined,
    },
    .{
        .title = "Project X",
        .uri = "project-x",
        .cover = undefined,
        .landing = undefined,
        .subprojects = undefined,
    },
    .{
        .title = "Cerulea",
        .uri = "cerulea",
        .cover = undefined,
        .landing = undefined,
        .subprojects = undefined,
    },
    .{
        .title = "The Project",
        .uri = "the-project",
        .cover = undefined,
        .landing = undefined,
        .subprojects = undefined,
    },
    .{
        .title = "Project Y",
        .uri = "project-y",
        .cover = undefined,
        .landing = undefined,
        .subprojects = undefined,
    },
    .{
        .title = "123456",
        .uri = "123456",
        .cover = undefined,
        .landing = undefined,
        .subprojects = undefined,
    },
    .{
        .title = "Lorem ipsum",
        .uri = "lorem-ipsum",
        .cover = undefined,
        .landing = undefined,
        .subprojects = undefined,
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
