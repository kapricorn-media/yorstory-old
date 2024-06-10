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

fn fillFromGoogleDriveThread(state: *ServerState) !void
{
    const folderId = "1Q5sM_dtJjpBtQX728PFU4TfYdIWCnnJ_";
    // DEBUG
    const key = "AIzaSyABIqpwoX4rSLyGz5nXqp2pknRagH_azkI";

    state.rwLockAlpha.lock();
    defer state.rwLockAlpha.unlock();

    try drive.fillFromGoogleDrive(folderId, &state.dynamicAlpha.data, key, state.allocator);
}

// const ServerCallbackError = server.Writer.Error || error {InternalServerError};

// const DynamicData = struct {
//     data: bigdata.Data,
//     portfolioJson: []const u8,
//     portfolio: portfolio.Portfolio,
// };

// const ServerState = struct {
//     allocator: std.mem.Allocator,

//     bigdataDynamicPath: []const u8,
//     dataStatic: bigdata.Data,
//     dynamic: DynamicData,
//     dynamicAlpha: DynamicData,
//     rwLockAlpha: std.Thread.RwLock,

//     const Self = @This();

//     pub fn init(
//         bigdataStaticPath: []const u8,
//         bigdataDynamicPath: []const u8,
//         portfolioJsonPath: []const u8,
//         allocator: std.mem.Allocator) !Self
//     {
//         var self: Self = .{
//             .allocator = allocator,
//             .bigdataDynamicPath = bigdataDynamicPath,
//             .dataStatic = undefined,
//             .dynamic = undefined,
//             .dynamicAlpha = undefined,
//             .rwLockAlpha = std.Thread.RwLock{},
//         };

//         const cwd = std.fs.cwd();
//         const porfolioJsonFile = try cwd.openFile(portfolioJsonPath, .{});
//         defer porfolioJsonFile.close();
//         self.dynamic.portfolioJson = try porfolioJsonFile.readToEndAlloc(allocator, 1024 * 1024 * 1024);
//         self.dynamic.portfolio = try portfolio.Portfolio.init(self.dynamic.portfolioJson, allocator);
//         self.dynamicAlpha.portfolioJson = try allocator.dupe(u8, self.dynamic.portfolioJson);
//         self.dynamicAlpha.portfolio = try portfolio.Portfolio.init(self.dynamicAlpha.portfolioJson, allocator);

//         try self.dataStatic.loadFromFile(bigdataStaticPath, allocator);
//         try self.dynamic.data.loadFromFile(bigdataDynamicPath, allocator);
//         try self.dynamicAlpha.data.loadFromFile(bigdataDynamicPath, allocator);

//         return self;
//     }

//     pub fn deinit(self: *Self) void
//     {
//         self.dynamic.portfolio.deinit(self.allocator);
//         self.allocator.free(self.dynamic.portfolioJson);
//         self.dynamicAlpha.portfolio.deinit(self.allocator);
//         self.allocator.free(self.dynamicAlpha.portfolioJson);
//         self.dataStatic.deinit();
//         self.dynamic.data.deinit();
//         self.dynamicAlpha.data.deinit();
//     }
// };

// fn isAuthenticated(request: server.Request) bool
// {
//     const auth = http.getHeader(request, "auth") orelse return false;
//     const authRef = std.os.getenv("AUTH_KEY") orelse return false;
//     return std.mem.eql(u8, auth, authRef);
// }

fn isAuthenticated(req: *httpz.Request, allocator: std.mem.Allocator) bool
{
    _ = req;
    _ = allocator;
    return true;
    // const auth = req.header("auth") orelse return false;
    // const authRef = std.process.getEnvVarOwned(allocator, "AUTH_KEY") catch {
    //     std.log.err("Failed to load AUTH_KEY env variable", .{});
    //     return false;
    // };
    // defer allocator.free(authRef);
    // return std.mem.eql(u8, auth, authRef);
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
                    // try server.writeCode(writer, ._401);
                    // try server.writeEndHeader(writer);
                    return;
                }

                if (isAlpha) {
                    res.status = 403;
                    // try server.writeCode(writer, ._403);
                    // try server.writeEndHeader(writer);
                    return;
                }

                if (std.mem.eql(u8, req.url.path, "/drive")) {
                    // const folderId = "1Q5sM_dtJjpBtQX728PFU4TfYdIWCnnJ_";
                    // DEBUG
                    // const key = "AIzaSyABIqpwoX4rSLyGz5nXqp2pknRagH_azkI";
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

                    const folderId = "1Q5sM_dtJjpBtQX728PFU4TfYdIWCnnJ_";
                    const key = "AIzaSyABIqpwoX4rSLyGz5nXqp2pknRagH_azkI";
                    try drive.fillFromGoogleDrive(folderId, &state.dynamicAlpha.data, key, state.allocator);
                    // _ = try std.Thread.spawn(.{}, fillFromGoogleDriveThread, .{state});
                    // try drive.fillFromGoogleDrive(folderId, &state.dynamicAlpha.data, key, state.allocator);

                    try res.writer().writeByte('y');
                    // try server.writeCode(writer, ._200);
                    // try server.writeEndHeader(writer);
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
        // const data = if (isAlpha) &state.dynamicAlpha.data else &state.dynamic.data;
        try app.server_utils.serverAppEndpoints(req, res, &state.dataStatic, PATH_WASM, false, DEBUG);
    }
    if (!app.server_utils.responded(res)) {
        // const data = if (isAlpha) &state.dynamicAlpha.data else &state.dynamic.data;
        try app.server_utils.serverAppEndpoints(req, res, &state.dynamic.data, PATH_WASM, true, DEBUG);
    }

    if (!app.server_utils.responded(res)) {
        res.status = 404;
    }
}

// fn serverCallback(
//     state: *ServerState,
//     request: server.Request,
//     writer: server.Writer) !void
// {
//     const host = http.getHeader(request, "Host") orelse return error.NoHost;
//     const isAdmin = std.mem.startsWith(u8, host, "admin.");
//     const isAlpha = std.mem.startsWith(u8, host, "alpha.");
//     const dynamicMap = if (isAlpha) &state.dynamicAlpha.data.map else &state.dynamic.data.map;
//     const portfolioJson = if (isAlpha) state.dynamicAlpha.portfolioJson else state.dynamic.portfolioJson;
//     const pf = if (isAlpha) state.dynamicAlpha.portfolio else state.dynamic.portfolio;
//     if (isAlpha) {
//         state.rwLockAlpha.lockShared();
//     }
//     defer {
//         if (isAlpha) {
//             state.rwLockAlpha.unlockShared();
//         }
//     }

//     const allocator = state.allocator;
//     var arena = std.heap.ArenaAllocator.init(allocator);
//     defer arena.deinit();
//     const tempAllocator = arena.allocator(); 

//     switch (request.method) {
//         .Get => {
//             var isPortfolioUri = false;
//             for (pf.projects) |project| {
//                 if (std.mem.eql(u8, request.uri, project.uri)) {
//                     isPortfolioUri = true;
//                 }
//             }

//             if (std.mem.eql(u8, request.uri, "/webgl_png")) {
//                 if (request.queryParams.len != 1) {
//                     try server.writeCode(writer, ._400);
//                     try server.writeEndHeader(writer);
//                     return;
//                 }

//                 const path = request.queryParams[0];
//                 if (!std.mem.eql(u8, path.name, "path")) {
//                     try server.writeCode(writer, ._400);
//                     try server.writeEndHeader(writer);
//                     return;
//                 }

//                 const data = state.dataStatic.map.get(path.value) orelse blk: {
//                     if (dynamicMap.get(path.value)) |d| {
//                         break :blk d;
//                     }
//                     try server.writeCode(writer, ._404);
//                     try server.writeEndHeader(writer);
//                     return;
//                 };
//                 try server.writeCode(writer, ._200);
//                 try server.writeContentLength(writer, data.len);
//                 try server.writeEndHeader(writer);
//                 try writer.writeAll(data);
//             } else if (std.mem.eql(u8, request.uri, "/main.wasm")) {
//                 try server.writeFileResponse(writer, WASM_PATH, tempAllocator);
//             } else if (std.mem.eql(u8, request.uri, "/portfolio")) {
//                 try server.writeCode(writer, ._200);
//                 try server.writeContentLength(writer, portfolioJson.len);
//                 try server.writeContentType(writer, .ApplicationJson);
//                 try server.writeEndHeader(writer);
//                 try writer.writeAll(portfolioJson);
//             } else {
//                 const uri = if (std.mem.eql(u8, request.uri, "/") or isPortfolioUri) "/wasm.html" else request.uri;
//                 if (DEBUG) {
//                     // For faster iteration
//                     // TODO this path can change
//                     server.serveStatic(writer, uri, "deps/zigkm-common/src/app/static", tempAllocator) catch |err| switch (err) {
//                         error.FileNotFound => {
//                             try server.serveStatic(writer, uri, "static", tempAllocator);
//                         },
//                         else => return err,
//                     };
//                 } else {
//                     const data = state.dataStatic.map.get(uri) orelse {
//                         try server.writeCode(writer, ._404);
//                         try server.writeEndHeader(writer);
//                         return;
//                     };
//                     try server.writeCode(writer, ._200);
//                     try server.writeContentLength(writer, data.len);
//                     if (server.getFileContentType(uri)) |contentType| {
//                         try server.writeContentType(writer, contentType);
//                     }
//                     try server.writeEndHeader(writer);
//                     try writer.writeAll(data);
//                 }
//             }
//         },
//         .Post => {
//             if (isAdmin) {
//                 if (isAdmin and !isAuthenticated(request)) {
//                     try server.writeCode(writer, ._401);
//                     try server.writeEndHeader(writer);
//                     return;
//                 }

//                 if (isAlpha) {
//                     try server.writeCode(writer, ._403);
//                     try server.writeEndHeader(writer);
//                     return;
//                 }

//                 if (std.mem.eql(u8, request.uri, "/drive")) {
//                     const folderId = "1Q5sM_dtJjpBtQX728PFU4TfYdIWCnnJ_";
//                     const key = std.os.getenv("GOOGLE_DRIVE_API_KEY") orelse {
//                         std.log.err("Missing GOOGLE_DRIVE_API_KEY", .{});
//                         try server.writeCode(writer, ._500);
//                         try server.writeEndHeader(writer);
//                         return;
//                     };

//                     std.debug.assert(!isAlpha);
//                     if (!state.rwLockAlpha.tryLock()) {
//                         try server.writeCode(writer, ._503);
//                         try server.writeEndHeader(writer);
//                         return;
//                     }
//                     defer state.rwLockAlpha.unlock();

//                     try drive.fillFromGoogleDrive(folderId, &state.dynamicAlpha.data, key, tempAllocator);

//                     try server.writeCode(writer, ._200);
//                     try server.writeEndHeader(writer);
//                 } else if (std.mem.eql(u8, request.uri, "/save")) {
//                     // Back up old file
//                     const timestampMs = std.time.milliTimestamp();
//                     const backupPath = try std.fmt.allocPrint(tempAllocator, "{s}.{}", .{state.bigdataDynamicPath, timestampMs});
//                     const cwd = std.fs.cwd();
//                     try cwd.rename(state.bigdataDynamicPath, backupPath);

//                     // Save new file
//                     try state.dynamicAlpha.data.saveToFile(state.bigdataDynamicPath, tempAllocator);

//                     // Respond and restart server
//                     try server.writeCode(writer, ._200);
//                     try server.writeEndHeader(writer);
//                     std.os.exit(0);
//                 } else {
//                     try server.writeCode(writer, ._404);
//                     try server.writeEndHeader(writer);
//                 }
//             } else {
//                 try server.writeCode(writer, ._404);
//                 try server.writeEndHeader(writer);
//             }
//         },
//     }
// }

// fn serverCallbackWrapper(
//     state: *ServerState,
//     request: server.Request,
//     writer: server.Writer) ServerCallbackError!void
// {
//     serverCallback(state, request, writer) catch |err| {
//         std.log.err("serverCallback failed, error {}", .{err});
//         const code = switch (err) {
//             error.FileNotFound => http.Code._404,
//             else => http.Code._500,
//         };
//         try server.writeCode(writer, code);
//         try server.writeEndHeader(writer);
//         return error.InternalServerError;
//     };
// }

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

    var server = try httpz.ServerCtx(*ServerState, *ServerState).init(
        allocator, .{.port = port }, &state
    );

    var router = server.router();
    router.get("*", requestHandler);
    router.post("*", requestHandler);

    std.log.info("Listening on port {}", .{port});
    try server.listen(); 
}

// pub fn main() !void
// {
//     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//     defer {
//         if (gpa.deinit()) {
//             std.log.err("GPA detected leaks", .{});
//         }
//     }
//     const allocator = gpa.allocator();

//     const args = try std.process.argsAlloc(allocator);
//     defer allocator.free(args);
//     if (args.len < 5) {
//         std.log.err("Expected arguments: <bigdata-static> <bigdata-dynamic> <portfolio-json> <port> [<https-chain-path> <https-key-path>]", .{});
//         return error.BadArgs;
//     }

//     const bigdataStaticPath = args[1];
//     const bigdataDynamicPath = args[2];
//     const portfolioJsonPath = args[3];
//     var state = try ServerState.init(
//         bigdataStaticPath, bigdataDynamicPath, portfolioJsonPath, allocator
//     );
//     defer state.deinit();

//     const serverArgs = args[4..];
//     try server.startFromCmdArgs(SERVER_IP, serverArgs, &state, serverCallbackWrapper, allocator);
// }
