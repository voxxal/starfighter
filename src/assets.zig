const zstbi = @import("zstbi");
const sg = @import("sokol").gfx;

pub const root = "./assets/";

fn loadImage(path: [:0]const u8, desc: sg.ImageDesc) sg.Image {
    var image_src: zstbi.Image = zstbi.Image.loadFromFile(path, 4) catch unreachable;
    defer zstbi.Image.deinit(&image_src);

    var image_desc: sg.ImageDesc = desc;
    image_desc.pixel_format = .RGBA8;
    image_desc.data.subimage[0][0] = sg.asRange(image_src.data);
    return sg.makeImage(image_desc);
}

pub var ship: sg.Image = undefined;
pub var player_bullet: sg.Image = undefined;
pub var alien_basic: sg.Image = undefined;

pub var tormenter_base: sg.Image = undefined;
pub var tormenter_eye: sg.Image = undefined;
pub var tormenter_eye_broken: sg.Image = undefined;
pub var tormenter_laser: sg.Image = undefined;
pub var tormenter_bullet: sg.Image = undefined;

pub fn loadAssets() void {
    ship = loadImage(root ++ "ship.png", .{ .width = 16, .height = 24 });
    player_bullet = loadImage(root ++ "player_bullet.png", .{ .width = 8, .height = 8 });
    alien_basic = loadImage(root ++ "alien_basic.png", .{ .width = 16, .height = 16 });

    tormenter_base = loadImage(root ++ "tormenter_base.png", .{ .width = 800, .height = 150 });
    tormenter_eye = loadImage(root ++ "tormenter_eye.png", .{ .width = 102, .height = 48 });
    tormenter_eye_broken = loadImage(root ++ "tormenter_eye_broken.png", .{ .width = 102, .height = 48 });
    tormenter_laser = loadImage(root ++ "tormenter_laser.png", .{ .width = 8, .height = 1 });
    tormenter_bullet = loadImage(root ++ "tormenter_bullet.png", .{ .width = 16, .height = 16 });
}
