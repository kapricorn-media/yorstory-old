const builtin = @import("builtin");
const std = @import("std");

const google = @import("zigkm-google");

const app = @import("zigkm-app");
const bigdata = app.bigdata;
const zigimg = @import("zigimg");

pub const log_level: std.log.Level = switch (builtin.mode) {
    .Debug => .debug,
    .ReleaseSafe => .info,
    .ReleaseFast => .info,
    .ReleaseSmall => .info,
};

const CHUNK_SIZE = 512 * 1024;

fn readIntBigEndian(comptime T: type, data: []const u8) !T
{
    var stream = std.io.fixedBufferStream(data);
    var reader = stream.reader();
    return reader.readIntBig(T);
}

fn deserializeMapValue(comptime T: type, data: []const u8, value: *T) !usize
{
    switch (@typeInfo(T)) {
        .Int => {
            const valueU64 = try readIntBigEndian(u64, data);
            value.* = @intCast(T, valueU64);
            return 8;
        },
        .Pointer => |tiPtr| {
            switch (tiPtr.size) {
                .Slice => {
                    if (comptime tiPtr.child != u8) {
                        @compileLog("Unsupported slice type", tiPtr.child);
                        unreachable;
                    }
                    const len = try readIntBigEndian(u64, data);
                    if (data.len < len + 8) {
                        return error.BadData;
                    }
                    value.* = data[8..8+len];
                    return 8 + len;
                },
                else => {
                    @compileLog("Unsupported type", T);
                    unreachable;
                },
            }
        },
        .Array => |tiArray| {
            switch (tiArray.child) {
                u8 => {
                    std.mem.copy(u8, value, data[0..tiArray.len]);
                    return tiArray.len;
                },
                else => {
                    var i: usize = 0;
                    for (value.*) |*v| {
                        const n = try deserializeMapValue(tiArray.child, data[i..], v);
                        i += n;
                    }
                    return i;
                }
            }
        },
        .Struct => |tiStruct| {
            var i: usize = 0;
            inline for (tiStruct.fields) |f| {
                const n = try deserializeMapValue(f.field_type, data[i..], &@field(value, f.name));
                i += n;
            }
        },
        else => {
            @compileLog("Unsupported type", T);
            unreachable;
        },
    }

    return 0;
}

fn serializeMapValue(writer: anytype, value: anytype) !void
{
    var buf: [8]u8 = undefined;

    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .Int => {
            const valueU64 = @intCast(u64, value);
            std.mem.writeIntBig(u64, &buf, valueU64);
            try writer.writeAll(&buf);
        },
        .Pointer => |tiPtr| {
            switch (tiPtr.size) {
                .Slice => {
                    if (comptime tiPtr.child != u8) {
                        @compileLog("Unsupported slice type", tiPtr.child);
                        unreachable;
                    }
                    std.mem.writeIntBig(u64, &buf, value.len);
                    try writer.writeAll(&buf);
                    try writer.writeAll(value);
                },
                else => {
                    @compileLog("Unsupported type", T);
                    unreachable;
                },
            }
        },
        .Array => |tiArray| {
            switch (tiArray.child) {
                u8 => {
                    try writer.writeAll(&value);
                },
                else => {
                    for (value) |v| {
                        try serializeMapValue(writer, v);
                    }
                }
            }
        },
        .Struct => |tiStruct| {
            inline for (tiStruct.fields) |f| {
                try serializeMapValue(writer, @field(value, f.name));
            }
        },
        else => {
            @compileLog("Unsupported type", T);
            unreachable;
        },
    }
}

pub fn deserializeMap(
    comptime ValueType: type,
    data: []const u8,
    allocator: std.mem.Allocator) !std.StringHashMap(ValueType)
{
    const numEntries = blk: {
        var stream = std.io.fixedBufferStream(data);
        var reader = stream.reader();
        break :blk try reader.readIntBig(u64);
    };

    var map = std.StringHashMap(ValueType).init(allocator);
    errdefer map.deinit();

    var i: usize = 8;
    var n: usize = 0;
    while (n < numEntries) : (n += 1) {
        const pathEnd = std.mem.indexOfScalarPos(u8, data, i, 0) orelse return error.BadData;
        const path = data[i..pathEnd];
        if (pathEnd + 1 + 16 > data.len) {
            return error.BadData;
        }
        const intBuf = data[pathEnd+1..pathEnd+1+16];
        var intStream = std.io.fixedBufferStream(intBuf);
        var intReader = intStream.reader();
        const valueIndex = try intReader.readIntBig(u64);
        const valueSize = try intReader.readIntBig(u64);
        if (valueIndex > data.len) {
            return error.BadData;
        }
        if (valueIndex + valueSize > data.len) {
            return error.BadData;
        }
        const valueBytes = data[valueIndex..valueIndex+valueSize];

        i = pathEnd + 1 + 16;

        var v: ValueType = undefined;
        _ = try deserializeMapValue(ValueType, valueBytes, &v);
        try map.put(path, v);
    }

    return map;
}

pub fn serializeMap(
    comptime ValueType: type,
    map: std.StringHashMap(ValueType),
    allocator: std.mem.Allocator) ![]const u8
{
    var out = std.ArrayList(u8).init(allocator);
    defer out.deinit();
    var writer = out.writer();

    try writer.writeIntBig(u64, map.count());
    var mapIt = map.iterator();
    while (mapIt.next()) |entry| {
        try writer.writeAll(entry.key_ptr.*);
        try writer.writeByte(0);
        try writer.writeByteNTimes(0, 16); // filled later
    }
    var endOfKeys = out.items.len;

    var buf: [8]u8 = undefined;
    mapIt = map.iterator();
    var i: usize = @sizeOf(u64); // skip initial map.count()
    while (mapIt.next()) |entry| {
        const dataIndex = out.items.len;
        try serializeMapValue(writer, entry.value_ptr.*);
        const dataSize = out.items.len - dataIndex;

        i = std.mem.indexOfScalarPos(u8, out.items, i, 0) orelse return error.BadData;
        i += 1;
        if (i + 16 > out.items.len) {
            return error.BadData;
        }

        std.mem.writeIntBig(u64, &buf, dataIndex);
        std.mem.copy(u8, out.items[i..i+8], &buf);
        std.mem.writeIntBig(u64, &buf, dataSize);
        std.mem.copy(u8, out.items[i+8..i+16], &buf);
        i += 16;
        if (i > endOfKeys) {
            return error.BadData;
        }
    }

    return out.toOwnedSlice();
}

test {
    const allocator = std.testing.allocator;

    var map = std.StringHashMap(SourceEntry).init(allocator);
    defer map.deinit();

    var entry: SourceEntry = undefined;
    std.mem.set(u8, &entry.md5Checksum, 6);
    for (entry.children.buffer) |*e| {
        e.len = 0;
    }
    entry.children.len = 2;
    entry.children.set(0, "hello, world");
    entry.children.set(1, "goodbye, world");

    try map.put("entry1", entry);
    try map.put("entry1234", entry);

    var bytes = try serializeMap(SourceEntry, map, allocator);
    defer allocator.free(bytes);

    var mapOut = try deserializeMap(SourceEntry, bytes, allocator);
    defer mapOut.deinit();

    try std.testing.expectEqual(map.count(), mapOut.count());
    var mapIt = map.iterator();
    while (mapIt.next()) |e| {
        const key = e.key_ptr.*;
        const v = mapOut.get(key) orelse {
            std.log.err("Missing key {s}", .{key});
            return error.MissingKey;
        };
        const value = e.value_ptr.*;
        try std.testing.expectEqualSlices(u8, &value.md5Checksum, &v.md5Checksum);
        try std.testing.expectEqual(value.children.len, v.children.len);
        for (value.children.buffer) |_, i| {
            try std.testing.expectEqualStrings(value.children.buffer[i], v.children.buffer[i]);
        }
    }
}

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

    pub fn saveToFile(self: *const Self, filePath: []const u8, allocator: std.mem.Allocator) !void
    {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const tempAllocator = arena.allocator();

        var file = try std.fs.cwd().createFile(filePath, .{});
        defer file.close();

        const sourceMapSerialized = try serializeMap(SourceEntry, self.sourceMap, tempAllocator);
        try file.writeAll(sourceMapSerialized);
        const mapSerialized = try serializeMap([]const u8, self.map, tempAllocator);
        try file.writeAll(mapSerialized);
    }

    pub fn put(self: *Self, path: []const u8, data: []const u8, allocator: std.mem.Allocator) !void
    {
        const selfAllocator = self.arenaAllocator.allocator();

        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const tempAllocator = arena.allocator();

        var sourceEntry: SourceEntry = undefined;
        var md5 = std.crypto.hash.Md5.init(.{});
        md5.update(data);
        md5.final(&sourceEntry.md5Checksum);
        // Important to clear all children for serialization logic
        for (sourceEntry.children.buffer) |*e| {
            e.len = 0;
        }

        if (std.mem.endsWith(u8, path, ".psd")) {
            var psdFile: app.psd.PsdFile = undefined;
            try psdFile.load(data, tempAllocator);
            for (psdFile.layers) |l, i| {
                if (!l.visible) {
                    continue;
                }

                _ = i;
                // const layerPixelData = try psdFile.layers[i].getPixelData(null, tempAllocator);
                // std.log.info("Loaded layer {s}, {}x{}", .{l.name, layerPixelData.width, layerPixelData.height});
                // const chunkSize = bigdata.calculateChunkSize(slice.size, CHUNK_SIZE_MAX);
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
            const pathDupe = try selfAllocator.dupe(u8, path);
            sourceEntry.children.len = 1;
            sourceEntry.children.set(0, pathDupe);
            try self.sourceMap.put(pathDupe, sourceEntry);

            if (std.mem.endsWith(u8, path, ".png")) {
                const chunked = try bigdata.pngToChunkedFormat(data, CHUNK_SIZE, tempAllocator);
                try self.map.put(pathDupe, try selfAllocator.dupe(u8, chunked));
                std.log.info("- done ({}K -> {}K)", .{data.len / 1024, chunked.len / 1024});
            } else {
                try self.map.put(pathDupe, try selfAllocator.dupe(u8, data));
            }
        }
    }
};

fn calculateMd5Checksum(data: []const u8) [16]u8
{
    var buf: [16]u8 = undefined;
    var md5 = std.crypto.hash.Md5.init(.{});
    md5.update(data);
    md5.final(&buf);
    return buf;
}

fn fileExists(path: []const u8, md5Checksum: *const [16]u8, data: *const Data) bool
{
    if (data.sourceMap.get(path)) |src| {
        if (std.mem.eql(u8, &src.md5Checksum, md5Checksum)) {
            return true;
        }
    }
    return false;
}

fn addIfNewOrUpdatedFilesystem(
    path: []const u8, fileData: []const u8, data: *Data, allocator: std.mem.Allocator) !void
{
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const tempAllocator = arena.allocator();

    const md5 = calculateMd5Checksum(fileData);
    if (fileExists(path, &md5, data)) {
        std.log.info("Already in bigdata: {s}", .{path});
        return;
    }

    std.log.info("Inserting {s}", .{path});
    try data.put(path, fileData, tempAllocator);
}

fn doFilesystem(path: []const u8, allocator: std.mem.Allocator) !Data
{
    var data: Data = undefined;
    data.load(allocator);

    const cwd = std.fs.cwd();
    var dir = try cwd.openDir(path, .{});
    defer dir.close();

    var dirIterable = try cwd.openIterableDir(path, .{});
    defer dirIterable.close();

    var walker = try dirIterable.walk(allocator);
    defer walker.deinit();
    while (try walker.next()) |entry| {
        if (entry.kind != .File) {
            continue;
        }

        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const tempAllocator = arena.allocator();

        const file = try dir.openFile(entry.path, .{});
        defer file.close();
        const fileData = try file.readToEndAlloc(tempAllocator, 1024 * 1024 * 1024);

        const filePath = try std.fmt.allocPrint(tempAllocator, "/{s}", .{entry.path});
        try addIfNewOrUpdatedFilesystem(filePath, fileData, &data, tempAllocator);
    }

    return data;
}

fn addIfNewOrUpdatedDrive(
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

    var md5FromMetadata: [16]u8 = undefined;
    _ = try std.fmt.hexToBytes(&md5FromMetadata, fileData.md5Checksum);
    if (fileExists(path, md5FromMetadata, data)) {
        std.log.info("Already in bigdata: {s}", .{path});
        return;
    }

    std.log.info("Inserting {s}", .{path});
    const downloadResponse = try google.drive.downloadFile(file.id, authData, tempAllocator);
    if (downloadResponse.code != ._200) {
        std.log.err("File download failed with code {}, response:\n{s}", .{
            downloadResponse.code, downloadResponse.body
        });
        return error.downloadFile;
    }

    const md5 = calculateMd5Checksum(downloadResponse.body);
    if (!std.mem.eql(u8, md5FromMetadata, md5)) {
        return error.mismatchedChecksums;
    }

    try data.put(path, downloadResponse.body, tempAllocator);
}

fn doDrive(key: []const u8, allocator: std.mem.Allocator) !Data
{
    const publicFolderId = "1qGP8RjPHdgamDDBLQTV4yC6Qq9yGmL3w";
    const authData = google.auth.AuthData {.apiKey = key};

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
                    const path = try std.fmt.allocPrint(
                        allocator, "/images/PARALLAX/{s}", .{ff.name}
                    );
                    std.debug.print("    {s} [{s}]\n", .{ff.name, ff.typeData.file.md5Checksum});
                    try addIfNewOrUpdatedDrive(path, ff, authData, &data, allocator);
                }
            } else {
                // std.debug.print("Project: {s}\n", .{f.name});

                // var coverFound = false;
                // var stickerFound = false;
                // var galleryFound = false;
                // var listProject = try google.drive.listFiles(f.id, authData, allocator);
                // defer listProject.deinit();
                // for (listProject.files) |ff| {
                //     switch (ff.typeData) {
                //         .file => |fileData| {
                //             std.debug.print("    {s} [{s}]\n", .{ff.name, fileData.md5Checksum});
                //             const path = try std.fmt.allocPrint(
                //                 allocator, "/images/{s}/{s}", .{f.name, ff.name}
                //             );
                //             if (std.mem.eql(u8, ff.name, "cover.png")) {
                //                 coverFound = true;
                //                 try addIfNewOrUpdated(path, ff, authData, &data, allocator);
                //             }
                //             if (std.mem.eql(u8, ff.name, "sticker-main.png")) {
                //                 stickerFound = true;
                //                 try addIfNewOrUpdated(path, ff, authData, &data, allocator);
                //             }
                //         },
                //         .folder => {
                //             if (std.mem.eql(u8, ff.name, "GALLERY")) {
                //                 galleryFound = true;
                //                 var listGallery = try google.drive.listFiles(ff.id, authData, allocator);
                //                 defer listGallery.deinit();
                //                 for (listGallery.files) |fff| {
                //                     std.debug.print("    {s}", .{fff.name});
                //                     switch (fff.typeData) {
                //                         .file => |fileData| {
                //                             std.debug.print(" [{s}]", .{fileData.md5Checksum});
                //                         },
                //                         .folder => {},
                //                     }
                //                     std.debug.print("\n", .{});
                //                 }
                //             }
                //         },
                //     }
                // }
                // if (!coverFound) {
                //     std.log.err("Project {s} missing cover.png", .{f.name});
                // }
                // if (!stickerFound) {
                //     std.log.err("Project {s} missing sticker-main.png", .{f.name});
                // }
                // if (!galleryFound) {
                //     std.log.err("Project {s} missing GALLERY", .{f.name});
                // }
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

    const args = try std.process.argsAlloc(allocator);
    defer allocator.free(args);
    if (args.len != 2) {
        std.log.err("Expected arguments: <api-key>/<path>", .{});
        return error.BadArgs;
    }

    const data1 = try doFilesystem(args[1], allocator);
    try data1.saveToFile("data1.bigdata", allocator);
    // const data2 = try doDrive(args[1], allocator);
    // _ = data2;

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
