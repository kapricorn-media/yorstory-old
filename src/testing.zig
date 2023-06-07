const builtin = @import("builtin");
const std = @import("std");

const google = @import("zigkm-google");
// const m = @import("zigkm-math");
const app = @import("zigkm-app");
const bigdata = app.bigdata;
// const zigimg = @import("zigimg");

pub const log_level: std.log.Level = switch (builtin.mode) {
    .Debug => .debug,
    .ReleaseSafe => .info,
    .ReleaseFast => .info,
    .ReleaseSmall => .info,
};


fn addIfNewOrUpdatedDrive(
    path: []const u8,
    file: google.drive.FileMetadata,
    authData: google.auth.AuthData,
    data: *bigdata.Data,
    allocator: std.mem.Allocator) !void
{
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const tempAllocator = arena.allocator();

    std.debug.assert(file.typeData == .file);
    const fileData = file.typeData.file;

    var md5FromMetadata: [16]u8 = undefined;
    _ = try std.fmt.hexToBytes(&md5FromMetadata, fileData.md5Checksum);
    if (bigdata.fileExists(path, md5FromMetadata, data)) {
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

    const md5 = bigdata.calculateMd5Checksum(downloadResponse.body);
    if (!std.mem.eql(u8, md5FromMetadata, md5)) {
        return error.mismatchedChecksums;
    }

    try data.put(path, downloadResponse.body, tempAllocator);
}

fn doDrive(key: []const u8, allocator: std.mem.Allocator) !bigdata.Data
{
    const publicFolderId = "1qGP8RjPHdgamDDBLQTV4yC6Qq9yGmL3w";
    const authData = google.auth.AuthData {.apiKey = key};

    var data: bigdata.Data = undefined;
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

    const data1 = try bigdata.doFilesystem(args[1], allocator);
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
