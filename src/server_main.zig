const builtin = @import("builtin");
const std = @import("std");

const app = @import("zigkm-app");
const bigdata = app.bigdata;
const httpz = @import("httpz");

const drive = @import("drive.zig");
const portfolio = @import("portfolio.zig");

pub usingnamespace @import("zigkm-stb").exports; // for stb linking

pub const log_level: std.log.Level = switch (builtin.mode) {
    .Debug => .debug,
    .ReleaseSafe => .info,
    .ReleaseFast => .info,
    .ReleaseSmall => .info,
};

const DEBUG = builtin.mode == .Debug;

const PATH_WASM = if (DEBUG) "zig-out/server/app.wasm" else "app.wasm";

const DynamicData = struct {
    data: bigdata.Data,
    portfolioJson: []const u8,
    portfolio: portfolio.Portfolio,
};

const ServerState = struct {
    allocator: std.mem.Allocator,
    dataStatic: bigdata.Data,
    bigdataDynamicPath: []const u8,
    dynamic: DynamicData,
    dynamicAlpha: DynamicData,
    rwLockAlpha: std.Thread.RwLock,

    const Self = @This();

    fn init(allocator: std.mem.Allocator, bigdataStaticPath: []const u8, bigdataDynamicPath: []const u8, portfolioJsonPath: []const u8) !Self
    {
        var self: Self = .{
            .allocator = allocator,
            .dataStatic = undefined,
            .bigdataDynamicPath = bigdataDynamicPath,
            .dynamic = undefined,
            .dynamicAlpha = undefined,
            .rwLockAlpha = .{},
        };

        const cwd = std.fs.cwd();
        const porfolioJsonFile = try cwd.openFile(portfolioJsonPath, .{});
        defer porfolioJsonFile.close();
        self.dynamic.portfolioJson = try porfolioJsonFile.readToEndAlloc(allocator, 1024 * 1024 * 1024);
        self.dynamic.portfolio = try portfolio.Portfolio.init(self.dynamic.portfolioJson, allocator);
        self.dynamicAlpha.portfolioJson = try allocator.dupe(u8, self.dynamic.portfolioJson);
        self.dynamicAlpha.portfolio = try portfolio.Portfolio.init(self.dynamicAlpha.portfolioJson, allocator);

        try self.dataStatic.loadFromFile(bigdataStaticPath, allocator);
        errdefer self.dataStatic.deinit();

        try self.dynamic.data.loadFromFile(bigdataDynamicPath, allocator);
        errdefer self.dynamic.data.deinit();
        try self.dynamicAlpha.data.loadFromFile(bigdataDynamicPath, allocator);
        errdefer self.dynamicAlpha.data.deinit();

        return self;
    }

    fn deinit(self: *Self) void
    {
        self.dynamic.data.deinit();
        self.dynamicAlpha.data.deinit();
    }
};

fn isAuthenticated(req: *httpz.Request, allocator: std.mem.Allocator) bool
{
    const auth = req.header("auth") orelse return false;
    const authRef = std.process.getEnvVarOwned(allocator, "AUTH_KEY") catch {
        std.log.err("Failed to load AUTH_KEY env variable", .{});
        return false;
    };
    defer allocator.free(authRef);
    return std.mem.eql(u8, auth, authRef);
}

fn requestHandler(state: *ServerState, req: *httpz.Request, res: *httpz.Response) !void
{
    var arena = std.heap.ArenaAllocator.init(state.allocator);
    defer arena.deinit();
    const tempAllocator = arena.allocator();

    const host = req.header("host") orelse req.header("Host") orelse return error.NoHost;
    const isAdmin = std.mem.startsWith(u8, host, "admin.");
    const isAlpha = std.mem.startsWith(u8, host, "alpha.");
    const isAuth = isAuthenticated(req, tempAllocator);
    const portfolioJson = if (isAlpha) state.dynamicAlpha.portfolioJson else state.dynamic.portfolioJson;
    const pf = if (isAlpha) state.dynamicAlpha.portfolio else state.dynamic.portfolio;
    if (isAlpha) {
        state.rwLockAlpha.lockShared();
    }
    defer {
        if (isAlpha) {
            state.rwLockAlpha.unlockShared();
        }
    }

    switch (req.method) {
        .GET => {
            var isPortfolioUri = false;
            for (pf.projects) |project| {
                if (std.mem.eql(u8, req.url.path, project.uri)) {
                    isPortfolioUri = true;
                }
            }
            if (isPortfolioUri) {
                req.url.path = "/wasm.html";
            } else if (std.mem.eql(u8, req.url.path, "/portfolio")) {
                res.content_type = .JSON;
                try res.writer().writeAll(portfolioJson);
            }
        },
        .POST => {
            if (isAdmin) {
                if (isAdmin and !isAuth) {
                    res.status = 401;
                    return;
                }

                if (isAlpha) {
                    res.status = 403;
                    return;
                }

                if (std.mem.eql(u8, req.url.path, "/drive")) {
                    // const folderId = "1Q5sM_dtJjpBtQX728PFU4TfYdIWCnnJ_";
                    // const key = std.process.getEnvVarOwned(tempAllocator, "GOOGLE_DRIVE_API_KEY") catch {
                    //     std.log.err("Missing GOOGLE_DRIVE_API_KEY", .{});
                    //     res.status = 500;
                    //     // try server.writeCode(writer, ._500);
                    //     // try server.writeEndHeader(writer);
                    //     return;
                    // };

                    // if (!state.rwLockAlpha.tryLock()) {
                    //     res.status = 503;
                    //     // try server.writeCode(writer, ._503);
                    //     // try server.writeEndHeader(writer);
                    //     return;
                    // }
                    // defer state.rwLockAlpha.unlock();

                    // try drive.fillFromGoogleDrive(folderId, &state.dynamicAlpha.data, key, state.allocator);

                    try res.writer().writeByte('y');
                } else if (std.mem.eql(u8, req.url.path, "/save")) {
                    // Back up old file
                    const timestampMs = std.time.milliTimestamp();
                    const backupPath = try std.fmt.allocPrint(tempAllocator, "{s}.{}", .{state.bigdataDynamicPath, timestampMs});
                    const cwd = std.fs.cwd();
                    try cwd.rename(state.bigdataDynamicPath, backupPath);

                    // Save new file
                    try state.dynamicAlpha.data.saveToFile(state.bigdataDynamicPath, tempAllocator);

                    // Respond and restart server
                    try res.writer().writeByte('y');
                    std.os.exit(0);
                }
            }
        },
        else => {},
    }

    if (!app.server_utils.responded(res)) {
        try app.server_utils.serverAppEndpoints(req, res, &state.dataStatic, PATH_WASM, false, DEBUG);
    }
    if (!app.server_utils.responded(res)) {
        try app.server_utils.serverAppEndpoints(req, res, &state.dynamic.data, PATH_WASM, true, DEBUG);
    }

    if (!app.server_utils.responded(res)) {
        res.status = 404;
    }
}

pub fn main() !void
{
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len != 5) {
        std.log.err("Expected arguments: datafile-static datafile-dynamic port portfolio-json", .{});
        return error.BadArgs;
    }

    const datafileStatic = args[1];
    const datafileDynamic = args[2];
    const portfolioJson = args[4];
    var state = try ServerState.init(allocator, datafileStatic, datafileDynamic, portfolioJson);
    defer state.deinit();

    const port = try std.fmt.parseUnsigned(u16, args[3], 10);

    var server = try httpz.ServerCtx(*ServerState, *ServerState).init(allocator, .{
        .port = port,
        .address = "0.0.0.0",
    }, &state);

    var router = server.router();
    router.get("*", requestHandler);
    router.post("*", requestHandler);

    std.log.info("Listening on port {}", .{port});
    try server.listen(); 
}
