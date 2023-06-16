const builtin = @import("builtin");
const std = @import("std");

const google = @import("zigkm-google");
const app = @import("zigkm-app");
const bigdata = app.bigdata;

fn addIfNewOrUpdatedDrive(
    path: []const u8,
    file: google.drive.FileMetadata,
    authData: google.auth.AuthData,
    data: *bigdata.Data,
    tempAllocator: std.mem.Allocator) !void
{

    std.debug.assert(file.typeData == .file);
    const fileData = file.typeData.file;

    var md5FromMetadata: [16]u8 = undefined;
    _ = try std.fmt.hexToBytes(&md5FromMetadata, fileData.md5Checksum);
    if (data.fileExists(path, &md5FromMetadata)) {
        std.log.info("Already in bigdata: {s}", .{path});
        return;
    }

    std.log.info("Inserting {s}", .{path});
    _ = authData;
    _ = tempAllocator;
    // const downloadResponse = try google.drive.downloadFile(file.id, authData, tempAllocator);
    // if (downloadResponse.code != ._200) {
    //     std.log.err("File download failed with code {}, response:\n{s}", .{
    //         downloadResponse.code, downloadResponse.body
    //     });
    //     return error.downloadFile;
    // }

    // const md5 = bigdata.calculateMd5Checksum(downloadResponse.body);
    // if (!std.mem.eql(u8, &md5FromMetadata, &md5)) {
    //     return error.mismatchedChecksums;
    // }

    // try data.put(path, downloadResponse.body, tempAllocator);
}

pub fn fillFromGoogleDrive(data: *bigdata.Data, key: []const u8, allocator: std.mem.Allocator) !void
{
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const tempAllocator = arena.allocator();

    const publicFolderId = "1Q5sM_dtJjpBtQX728PFU4TfYdIWCnnJ_";
    const authData = google.auth.AuthData {.apiKey = key};

    var projects = try google.drive.listFiles(publicFolderId, authData, tempAllocator);
    defer projects.deinit();
    for (projects.files) |f| {
        if (f.typeData == .folder) {
            if (std.mem.eql(u8, f.name, "PARALLAX")) {
                std.debug.print("Parallax scenes:\n", .{});
                var listParallax = try google.drive.listFiles(f.id, authData, tempAllocator);
                defer listParallax.deinit();
                for (listParallax.files) |ff| {
                    if (ff.typeData != .file) {
                        continue;
                    }
                    const path = try std.fmt.allocPrint(
                        tempAllocator, "/DRIVE/PARALLAX/{s}", .{ff.name}
                    );
                    std.debug.print("    {s} [{s}]\n", .{ff.name, ff.typeData.file.md5Checksum});
                    try addIfNewOrUpdatedDrive(path, ff, authData, data, tempAllocator);
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
}
