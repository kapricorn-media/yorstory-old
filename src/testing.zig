const std = @import("std");

const google = @import("zigkm-google");

const app = @import("zigkm-app");
const bigdata = app.bigdata;

const CHUNK_SIZE = 512 * 1024;

pub const SourceEntry = struct {
    md5Checksum: [16]u8,
    children: std.BoundedArray([]const u8, 32),
};

pub const Data = struct {
    arenaAllocator: std.heap.ArenaAllocator,
    sourceMap: std.StringHashMap(SourceEntry),
    map: std.StringHashMap([]const u8),
    bytes: ?[]const u8,

    const Self = @This();

    pub fn load(self: *Self, allocator: std.mem.Allocator) void
    {
        self.arenaAllocator = std.heap.ArenaAllocator.init(allocator);
        self.* = .{
            .arenaAllocator = self.arenaAllocator,
            .sourceMap = std.StringHashMap(SourceEntry).init(self.arenaAllocator.allocator()),
            .map = std.StringHashMap([]const u8).init(self.arenaAllocator.allocator()),
            .bytes = null,
        };
    }

    pub fn unload(self: *Self) void
    {
        self.arenaAllocator.deinit();
    }

    pub fn put(self: *Self, path: []const u8, data: []const u8, allocator: std.mem.Allocator) !void
    {
        const selfAllocator = self.arenaAllocator.allocator();

        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const tempAllocator = arena.allocator();

        var srcEntry: SourceEntry = undefined;
        var md5 = std.crypto.hash.Md5.init(.{});
        md5.update(data);
        md5.final(&srcEntry.md5Checksum);

        if (std.mem.endsWith(u8, path, ".png")) {
            const pathDupe = try selfAllocator.dupe(u8, path);
            srcEntry.children.len = 1;
            srcEntry.children.set(0, pathDupe);
            try self.sourceMap.put(pathDupe, srcEntry);

            const chunked = try bigdata.pngToChunkedFormat(data, CHUNK_SIZE, tempAllocator);
            try self.map.put(pathDupe, try selfAllocator.dupe(u8, chunked));
            std.log.info("- done ({}K -> {}K)", .{data.len / 1024, chunked.len / 1024});
        } else if (std.mem.endsWith(u8, path, ".psd")) {
            var psdFile: app.psd.PsdFile = undefined;
            try psdFile.load(data, tempAllocator);
            for (psdFile.layers) |l, i| {
                if (!l.visible) {
                    continue;
                }
                _ = i;
                // const dashInd = std.mem.indexOfScalar(u8, l.name, '-') orelse continue;
                // const pre = l.name[0..dashInd];
                // var allNumbers = true;
                // for (pre) |c| {
                //     if (!('0' <= c and c <= '9')) {
                //         allNumbers = false;
                //         break;
                //     }
                // }
                // if (!allNumbers) continue;

                // const safeAspect = 3;
                // const sizeX = @floatToInt(usize, @intToFloat(f32, psdFile.canvasSize.y) * safeAspect);
                // const parallaxSize = m.Vec2usize.init(sizeX, psdFile.canvasSize.y);
                // const topLeft = m.Vec2i.init(@divTrunc((@intCast(i32, psdFile.canvasSize.x) - @intCast(i32, sizeX)), 2), 0);
                // const layerPixelData = image.PixelData {
                //     .size = parallaxSize,
                //     .channels = 4,
                //     .data = try tempAllocator.alloc(u8, parallaxSize.x * parallaxSize.y * 4),
                // };
                // std.mem.set(u8, layerPixelData.data, 0);
                // const sliceDst = image.PixelDataSlice {
                //     .topLeft = m.Vec2usize.zero,
                //     .size = parallaxSize,
                // };
                // _ = try psdFile.layers[i].getPixelDataRectBuf(null, topLeft, layerPixelData, sliceDst);

                // const sliceAll = image.PixelDataSlice {
                //     .topLeft = m.Vec2usize.zero,
                //     .size = layerPixelData.size,
                // };
                // const sliceTrim = image.trim(layerPixelData, sliceAll);
                // const slice = blk: {
                //     const offsetLeftX = sliceTrim.topLeft.x - sliceAll.topLeft.x;
                //     const offsetRightX = (sliceAll.topLeft.x + sliceAll.size.x) - (sliceTrim.topLeft.x + sliceTrim.size.x);
                //     const offsetMin = std.math.min(offsetLeftX, offsetRightX);
                //     break :blk image.PixelDataSlice {
                //         .topLeft = m.Vec2usize.init(sliceAll.topLeft.x + offsetMin, sliceAll.topLeft.y),
                //         .size = m.Vec2usize.init(sliceAll.size.x - offsetMin * 2, sliceAll.size.y),
                //     };
                // };
                // const chunkSize = calculateChunkSize(slice.size, CHUNK_SIZE_MAX);
                // const chunked = try pixelDataToPngChunkedFormat(layerPixelData, slice, chunkSize, allocator);
                // const outputDir = entry.path[0..entry.path.len - 4];
                // const uri = try std.fmt.allocPrint(allocator, "/{s}/{s}.png", .{outputDir, l.name});
                // try entries.append(Entry {
                //     .uri = uri,
                //     .data = chunked,
                // });
                // std.log.info("wrote chunked layer as {s} ({}K)", .{uri, chunked.len / 1024});

                // const png = @import("png.zig");
                // const testPath = try std.fmt.allocPrint(tempAllocator, "{s}.png", .{l.name});
                // try png.writePngFile(testPath, layerPixelData, slice);
            }
        } else {
        }
    }
};

fn addIfNewOrUpdated(
    path: []const u8,
    file: google.drive.FileMetadata,
    authData: google.auth.AuthData,
    data: *Data,
    allocator: std.mem.Allocator) !void
{
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const tempAllocator = arena.allocator();

    std.debug.assert(file.typeData == .file);
    const fileData = file.typeData.file;

    var buf: [16]u8 = undefined;

    var shouldInsert = true;
    if (data.sourceMap.get(path)) |src| {
        _ = try std.fmt.hexToBytes(&buf, fileData.md5Checksum);
        if (std.mem.eql(u8, &src.md5Checksum, &buf)) {
            shouldInsert = false;
        }
    }

    if (!shouldInsert) {
        std.log.info("Already in bigdata: {s}", .{path});
        return;
    }

    std.log.info("Inserting {s}", .{path});
    const downloadResponse = try google.drive.downloadFile(file.id, authData, tempAllocator);
    try data.put(path, downloadResponse.body, tempAllocator);
}

fn doDrive(allocator: std.mem.Allocator) !Data
{
    const publicFolderId = "1qGP8RjPHdgamDDBLQTV4yC6Qq9yGmL3w";
    const authData = google.auth.AuthData {.apiKey = "AIzaSyAEvaqEhShE_ijUPUnrGHD1ZyWSS9xl-s4"};

    var data: Data = undefined;
    data.load(allocator);

    var projects = try google.drive.listFiles(publicFolderId, authData, allocator);
    defer projects.deinit();
    for (projects.files) |f| {
        if (f.typeData == .folder) {
            if (std.mem.eql(u8, f.name, "PARALLAX")) {
                std.debug.print("Parallax scenes:\n", .{});
                var listParallax = try google.drive.listFiles(f.id, authData, allocator);
                defer listParallax.deinit();
                for (listParallax.files) |ff| {
                    if (ff.typeData != .file) {
                        continue;
                    }
                    std.debug.print("    {s} [{s}]\n", .{ff.name, ff.typeData.file.md5Checksum});
                }
            } else {
                std.debug.print("Project: {s}\n", .{f.name});

                var coverFound = false;
                var stickerFound = false;
                var galleryFound = false;
                var listProject = try google.drive.listFiles(f.id, authData, allocator);
                defer listProject.deinit();
                for (listProject.files) |ff| {
                    switch (ff.typeData) {
                        .file => |fileData| {
                            std.debug.print("    {s} [{s}]\n", .{ff.name, fileData.md5Checksum});
                            const path = try std.fmt.allocPrint(
                                allocator, "/images/{s}/{s}", .{f.name, ff.name}
                            );
                            if (std.mem.eql(u8, ff.name, "cover.png")) {
                                coverFound = true;
                                try addIfNewOrUpdated(path, ff, authData, &data, allocator);
                            }
                            if (std.mem.eql(u8, ff.name, "sticker-main.png")) {
                                stickerFound = true;
                                try addIfNewOrUpdated(path, ff, authData, &data, allocator);
                            }
                        },
                        .folder => {
                            if (std.mem.eql(u8, ff.name, "GALLERY")) {
                                galleryFound = true;
                                var listGallery = try google.drive.listFiles(ff.id, authData, allocator);
                                defer listGallery.deinit();
                                for (listGallery.files) |fff| {
                                    std.debug.print("    {s}", .{fff.name});
                                    switch (fff.typeData) {
                                        .file => |fileData| {
                                            std.debug.print(" [{s}]", .{fileData.md5Checksum});
                                        },
                                        .folder => {},
                                    }
                                    std.debug.print("\n", .{});
                                }
                            }
                        },
                    }
                }
                if (!coverFound) {
                    std.log.err("Project {s} missing cover.png", .{f.name});
                }
                if (!stickerFound) {
                    std.log.err("Project {s} missing sticker-main.png", .{f.name});
                }
                if (!galleryFound) {
                    std.log.err("Project {s} missing GALLERY", .{f.name});
                }
            }
        }
    }

    return data;
}

pub fn main() !void
{
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // defer {
    //     if (gpa.deinit()) {
    //         std.log.err("GPA detected leaks", .{});
    //     }
    // }
    const allocator = gpa.allocator();

    const data = try doDrive(allocator);
    _ = data;

    // var buf1: [16]u8 = undefined;
    // var buf2: [16]u8 = undefined;

    // const cwd = std.fs.cwd();
    // const file = try cwd.openFile("static.bigdata", .{});
    // defer file.close();
    // var bigdataBytes = try file.readToEndAlloc(allocator, 1024 * 1024 * 1024);
    // defer allocator.free(bigdataBytes);
    // var map = std.StringHashMap([]const u8).init(allocator);
    // defer map.deinit();
    // try bigdata.load(bigdataBytes, &map);

    // const publicFolderId = "1qGP8RjPHdgamDDBLQTV4yC6Qq9yGmL3w";
    // const authData = google.auth.AuthData {.apiKey = "AIzaSyAEvaqEhShE_ijUPUnrGHD1ZyWSS9xl-s4"};

    // var projects = try google.drive.listFiles(publicFolderId, authData, allocator);
    // defer projects.deinit();
    // for (projects.files) |f| {
    //     if (f.typeData == .folder) {
    //         if (std.mem.eql(u8, f.name, "PARALLAX")) {
    //             std.debug.print("Parallax scenes:\n", .{});
    //             var listParallax = try google.drive.listFiles(f.id, authData, allocator);
    //             defer listParallax.deinit();
    //             for (listParallax.files) |ff| {
    //                 if (ff.typeData != .file) {
    //                     continue;
    //                 }
    //                 std.debug.print("    {s} [{s}]\n", .{ff.name, ff.typeData.file.md5Checksum});
    //             }
    //         } else {
    //             std.debug.print("Project: {s}\n", .{f.name});

    //             var coverFound = false;
    //             var stickerFound = false;
    //             var galleryFound = false;
    //             var listProject = try google.drive.listFiles(f.id, authData, allocator);
    //             defer listProject.deinit();
    //             for (listProject.files) |ff| {
    //                 switch (ff.typeData) {
    //                     .file => |fileData| {
    //                         std.debug.print("    {s} [{s}]\n", .{ff.name, fileData.md5Checksum});
    //                         const path = try std.fmt.allocPrint(
    //                             allocator, "/images/{s}/{s}", .{f.name, ff.name}
    //                         );
    //                         if (std.mem.eql(u8, ff.name, "cover.png")) {
    //                             coverFound = true;
    //                             if (map.get(path)) |data| {
    //                                 var md5 = std.crypto.hash.Md5.init(.{});
    //                                 md5.update(data);
    //                                 md5.final(&buf1);
    //                                 _ = try std.fmt.hexToBytes(&buf2, fileData.md5Checksum);
    //                                 if (!std.mem.eql(u8, &buf1, &buf2)) {
    //                                     std.log.info("{s} mismatched checksums", .{path});
    //                                 }
    //                             } else {
    //                                 std.log.info("{s} not found", .{path});
    //                             }
    //                         }
    //                         if (std.mem.eql(u8, ff.name, "sticker-main.png")) {
    //                             stickerFound = true;
    //                         }
    //                     },
    //                     .folder => {
    //                         if (std.mem.eql(u8, ff.name, "GALLERY")) {
    //                             galleryFound = true;
    //                             var listGallery = try google.drive.listFiles(ff.id, authData, allocator);
    //                             defer listGallery.deinit();
    //                             for (listGallery.files) |fff| {
    //                                 std.debug.print("    {s}", .{fff.name});
    //                                 switch (fff.typeData) {
    //                                     .file => |fileData| {
    //                                         std.debug.print(" [{s}]", .{fileData.md5Checksum});
    //                                     },
    //                                     .folder => {},
    //                                 }
    //                                 std.debug.print("\n", .{});
    //                             }
    //                         }
    //                     },
    //                 }
    //             }
    //             if (!coverFound) {
    //                 std.log.err("Project {s} missing cover.png", .{f.name});
    //             }
    //             if (!stickerFound) {
    //                 std.log.err("Project {s} missing sticker-main.png", .{f.name});
    //             }
    //             if (!galleryFound) {
    //                 std.log.err("Project {s} missing GALLERY", .{f.name});
    //             }
    //         }
    //     }
    // }
}
