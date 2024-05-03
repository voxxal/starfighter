pub const packages = struct {
    pub const @"122034cf4aca9f97fea3c34f3e9fe92e56f08e2160efe3c95d7ec89260e621426a81" = struct {
        pub const build_root = "/home/voxal/.cache/zig/p/122034cf4aca9f97fea3c34f3e9fe92e56f08e2160efe3c95d7ec89260e621426a81";
        pub const deps: []const struct { []const u8, []const u8 } = &.{};
    };
    pub const @"12204b76dc14c74da9d61d01b5bd7a4fbfd0614aa7cc0a7428de0742129203ca5008" = struct {
        pub const build_root = "/home/voxal/.cache/zig/p/12204b76dc14c74da9d61d01b5bd7a4fbfd0614aa7cc0a7428de0742129203ca5008";
        pub const build_zig = @import("12204b76dc14c74da9d61d01b5bd7a4fbfd0614aa7cc0a7428de0742129203ca5008");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
            .{ "emsdk", "122034cf4aca9f97fea3c34f3e9fe92e56f08e2160efe3c95d7ec89260e621426a81" },
        };
    };
    pub const @"12205dbec9f917a3ab61ca65900dce7a04c9ec4348d0e2241a9c246b9c2d131d061b" = struct {
        pub const build_root = "/home/voxal/.cache/zig/p/12205dbec9f917a3ab61ca65900dce7a04c9ec4348d0e2241a9c246b9c2d131d061b";
        pub const build_zig = @import("12205dbec9f917a3ab61ca65900dce7a04c9ec4348d0e2241a9c246b9c2d131d061b");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
};

pub const root_deps: []const struct { []const u8, []const u8 } = &.{
    .{ "sokol", "12204b76dc14c74da9d61d01b5bd7a4fbfd0614aa7cc0a7428de0742129203ca5008" },
    .{ "zlm", "12205dbec9f917a3ab61ca65900dce7a04c9ec4348d0e2241a9c246b9c2d131d061b" },
};
