const std = @import("std");
const sokol = @import("sokol");
const zlm = @import("zlm");
const assets = @import("./assets.zig");
const zstbi = @import("zstbi");

const ArrayList = std.ArrayList;

const Vec2 = zlm.Vec2;
const Mat4 = zlm.Mat4;

const sg = sokol.gfx;
const sapp = sokol.app;
const sglue = sokol.glue;
const slog = sokol.log;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

fn hex(comptime str: []const u8) switch (str.len) {
    7 => @Vector(3, f32),
    9 => @Vector(4, f32),
    else => @compileError("die"),
} {
    switch (str.len) {
        7 => {
            return @Vector(3, f32){
                @as(f32, @floatFromInt(std.fmt.parseInt(u8, str[1..3], 16) catch unreachable)) / 255,
                @as(f32, @floatFromInt(std.fmt.parseInt(u8, str[3..5], 16) catch unreachable)) / 255,
                @as(f32, @floatFromInt(std.fmt.parseInt(u8, str[5..7], 16) catch unreachable)) / 255,
            };
        },

        9 => {
            return @Vector(4, f32){
                @as(f32, @floatFromInt(std.fmt.parseInt(u8, str[1..3], 16) catch unreachable)) / 255,
                @as(f32, @floatFromInt(std.fmt.parseInt(u8, str[3..5], 16) catch unreachable)) / 255,
                @as(f32, @floatFromInt(std.fmt.parseInt(u8, str[5..7], 16) catch unreachable)) / 255,
                @as(f32, @floatFromInt(std.fmt.parseInt(u8, str[7..9], 16) catch unreachable)) / 255,
            };
        },
        else => unreachable,
    }
}

const Actor = struct {
    pos: Vec2 = Vec2.zero,
    vel: Vec2 = Vec2.zero,
    size: Vec2,
    drag: f32 = 0.65,
    z: f32 = 1,

    sprite: sg.Image,
    flags: u32 = 0,
    active: bool = true,

    pub fn collides(self: @This(), other: @This()) bool {
        return other.pos.x + other.size.x > self.pos.x and
            other.pos.x < self.pos.x + self.size.x and
            other.pos.y + other.size.y > self.pos.y and
            other.pos.y < self.pos.y + self.size.y;
    }

    pub fn update(self: *@This(), dt: f32) void {
        self.pos = self.pos.add(self.vel.scale(dt));
        self.vel = self.vel.scale(self.drag);
    }

    pub fn model(self: @This()) Mat4 {
        const res = Mat4.createScale(self.size.x, self.size.y, 1);
        //return res.mul(Mat4.createTranslation(zlm.vec3(self.pos.x, self.pos.y, self.z)));
        return res.mul(Mat4.createTranslation(self.pos.swizzle("xy0")));
    }

    pub fn draw(self: @This(), tint: @Vector(4, f32)) void {
        if (self.active) pushQuad(self.model().mul(state.gfx.projection), self.sprite, tint, self.z);
    }
};

const Ship = struct {
    const SHOT_COOLDOWN = 0.1;
    actor: Actor = .{
        .size = zlm.vec2(24, 36),
        .sprite = .{ .id = 0 },
        .z = 0.2,
    },
    accel: f32 = 5000,
    shot_cooldown: f32 = 0,
    respawn: f32 = 0,

    pub fn shoot(self: *@This(), dt: f32) !void {
        self.shot_cooldown -= dt;
        if (self.shot_cooldown > 0) return;
        try state.game.hazards.append(.{
            .actor = .{
                .size = zlm.vec2(8, 8),
                .pos = zlm.vec2(self.actor.pos.x + self.actor.size.x / 2 - 4, self.actor.pos.y),
                .sprite = assets.player_bullet,
                .vel = zlm.vec2(0, -500),
                .drag = 1,
                .z = 0.1,
            },
            .friendly = true,
            .specific = .{ .bullet = {} },
        });

        self.shot_cooldown = SHOT_COOLDOWN;
    }
};

const AlienType = enum {
    basic,
    tormenter,
};

const AlienSpecific = union(AlienType) {
    basic: void,
    tormenter: struct {
        eye_health: [3]f32 = [_]f32{ 35, 35, 35 },
        eye_actors: [3]Actor,
        eye_shooting: [3]bool = [_]bool{ false, false, false },
        laser_cooldown: f32 = 5,
    },
};

const Alien = struct {
    specific: AlienSpecific = .{ .basic = {} },
    actor: Actor,
    health: f32 = 3,
    damage_tint: f32 = 0,

    // returns is dead
    pub fn damage(self: *@This(), amount: f32) bool {
        self.health -= amount;
        self.damage_tint = 1;
        return self.health <= 0;
    }

    pub fn update(self: *@This(), dt: f32) void {
        switch (self.specific) {
            .basic => {},
            .tormenter => |*tormenter| {
                tormenter.laser_cooldown -= dt;
                // TODO a lot of unessasary calls when all 3 eyes are destroyed, this will probably be fixed with the missiles later.
                if (tormenter.laser_cooldown <= 1.5 and std.mem.eql(bool, &tormenter.eye_shooting, &[3]bool{ false, false, false })) {
                    for (&tormenter.eye_shooting, tormenter.eye_health) |*shooting, hp| {
                        if (hp > 0 and state.rand.random().float(f32) > 0.5) {
                            shooting.* = true;
                        }
                    }
                }
                if (tormenter.laser_cooldown <= 0) {
                    var num_shooting: f32 = 0;
                    for (tormenter.eye_actors, tormenter.eye_shooting) |eye, shooting| {
                        if (!shooting) continue;
                        num_shooting += 1;
                        state.game.hazards.append(.{
                            .specific = .{ .tormenter_laser = .{} },
                            .actor = .{
                                .size = zlm.vec2(eye.size.x, 600),
                                .pos = eye.pos,
                                .sprite = assets.tormenter_laser,
                                .vel = zlm.vec2(0, 0),
                                .drag = 1,
                                .z = 0.8,
                            },
                            .damage = 1,
                            .friendly = false,
                        }) catch @panic("failed to add laser to hazards");
                    }
                    tormenter.laser_cooldown = 5;
                    tormenter.eye_shooting = [_]bool{ false, false, false };

                    shake(num_shooting * 5, 1.5);
                }
            },
        }
        self.actor.update(dt);
    }

    pub fn draw(self: @This()) void {
        switch (self.specific) {
            .basic => {
                const tint = if (self.damage_tint <= 0) WHITE else @Vector(4, f32){
                    1,
                    lerp(1, 0.5, self.damage_tint),
                    lerp(1, 0.5, self.damage_tint),
                    1,
                };
                self.actor.draw(tint);
            },
            .tormenter => |tormenter| {
                const tint = if (self.damage_tint <= 0) WHITE else @Vector(4, f32){
                    1,
                    lerp(1, 0.8, self.damage_tint),
                    lerp(1, 0.8, self.damage_tint),
                    1,
                };
                self.actor.draw(tint);

                for (tormenter.eye_actors, tormenter.eye_shooting) |eye, shooting| {
                    eye.draw(WHITE);
                    if (shooting) {
                        const model = Mat4.createScale(eye.size.x, 600, 1);
                        pushQuad(
                            model.mul(Mat4.createTranslation(eye.pos.swizzle("xy0"))).mul(state.gfx.projection),
                            assets.tormenter_laser,
                            .{ 1, 1, 1, 0.25 },
                            0.9,
                        );
                    }
                }
            },
        }
    }

    pub fn onCollide(self: *@This(), hazard: *Hazard) struct { remove_self: bool, remove_hazard: bool } {
        switch (self.specific) {
            .basic => {
                const dead = self.damage(hazard.damage);
                if (dead) {
                    shake(5, 0.25);
                }
                return .{ .remove_self = dead, .remove_hazard = true };
            },
            .tormenter => |*tormenter| {
                var remove_hazard = false;
                var destroyed_eyes: u4 = 0;
                for (&tormenter.eye_actors, &tormenter.eye_health, 0..) |*actor, *health, i| {
                    if (actor.collides(hazard.actor) and health.* > 0.0) {
                        health.* -= hazard.damage;
                        if (health.* <= 0) {
                            actor.sprite = assets.tormenter_eye_broken;
                            tormenter.eye_shooting[i] = false;
                        }
                        remove_hazard = true;
                    } else if (health.* <= 0.0) destroyed_eyes += 1;
                }

                var remove_self = false;
                if (hazard.actor.pos.y <= 125) {
                    remove_hazard = true;
                    if (destroyed_eyes == 3) {
                        remove_self = self.damage(hazard.damage);
                    }
                }

                if (remove_self) state.game.tormenter = .defeated;

                return .{ .remove_self = remove_self, .remove_hazard = remove_hazard };
            },
        }
    }
};

const HazardType = enum {
    bullet,
    tormenter_laser,
};

const HazardSpecific = union(HazardType) {
    bullet: void,
    tormenter_laser: struct {
        lifetime: f32 = 2,
    },
};

const Hazard = struct {
    specific: HazardSpecific,
    actor: Actor,
    friendly: bool,
    damage: f32 = 1,

    pub fn update(
        self: *@This(),
        dt: f32,
    ) struct { remove_self: bool } {
        switch (self.specific) {
            .bullet => {
                self.actor.update(dt);
                return .{
                    .remove_self = self.actor.pos.x > 800 or self.actor.pos.x + self.actor.size.x < 0 or self.actor.pos.y + self.actor.size.y < 0 or self.actor.pos.y > 600,
                };
            },
            .tormenter_laser => |*laser| {
                laser.lifetime -= dt;
                if (laser.lifetime < 0) {
                    return .{ .remove_self = true };
                }
            },
        }

        return .{ .remove_self = false };
    }
};

const Scene = enum {
    start,
    game,
};

const Vertex = packed struct {
    pos: @Vector(3, f32),
    tex: @Vector(2, f32),
    tint: @Vector(4, f32),
};

const GfxState = struct {
    quad_batch: [1024]Vertex align(1) = [_]Vertex{undefined} ** 1024,
    quad_batch_index: u16 = 0,
    quad_batch_tex: sg.Image = .{ .id = 0 },
    bind: sg.Bindings = .{},
    pip: sg.Pipeline = undefined,
    pass_action: sg.PassAction = undefined,
    projection: Mat4 = undefined,
    screen_shake: f32 = 0,
    screen_shake_duration: f32 = 0,
};

fn shake(strength: f32, duration: f32) void {
    if (strength >= state.gfx.screen_shake or (strength < state.gfx.screen_shake and state.gfx.screen_shake_duration < 0.1)) {
        state.gfx.screen_shake = strength;
        state.gfx.screen_shake_duration = duration;
    }
}

const BossStatus = enum {
    unspawned,
    alive,
    defeated,
};

const State = struct {
    scene: Scene = .start,
    rand: std.Random.Xoshiro256 = undefined,
    input: struct {
        up: bool = false,
        down: bool = false,
        left: bool = false,
        right: bool = false,
        shoot: bool = false,
    } = .{},
    game: struct {
        score: u32 = 0,
        tormenter: BossStatus = .unspawned,
        ship: Ship = undefined,
        aliens: ArrayList(Alien) = undefined,
        hazards: ArrayList(Hazard) = undefined,
    } = .{},
    gfx: GfxState = .{},
};

var state: State = .{};

fn resetGame() void {
    state.game.ship = .{};
    state.game.ship.actor.sprite = assets.ship;
    state.game.ship.actor.pos = zlm.vec2(400 - state.game.ship.actor.size.x, 400);
    state.game.aliens = ArrayList(Alien).init(gpa.allocator());
    for (0..3) |y| {
        for (0..16) |x| {
            state.game.aliens.append(.{
                .actor = .{ .pos = zlm.vec2(@as(f32, @floatFromInt(x)) * 50 + 5, @as(f32, @floatFromInt(y)) * 40 + 10), .size = zlm.vec2(24, 24), .sprite = assets.alien_basic, .z = 0.5 },
            }) catch @panic("failed to append new alien");
        }
    }
    state.game.hazards = ArrayList(Hazard).init(gpa.allocator());
}

fn spawnTormenter() void {
    state.game.aliens.append(.{
        .health = 100,
        .actor = .{
            .pos = Vec2.zero,
            .size = zlm.vec2(800, 150),
            .sprite = assets.tormenter_base,
            .z = 0.5,
        },
        .specific = .{ .tormenter = .{
            .eye_health = [_]f32{ 15, 15, 15 },
            .eye_actors = [_]Actor{
                .{ .pos = zlm.vec2(85, 100), .size = zlm.vec2(102, 48), .sprite = assets.tormenter_eye, .z = 0.4 },
                .{ .pos = zlm.vec2(360, 100), .size = zlm.vec2(102, 48), .sprite = assets.tormenter_eye, .z = 0.4 },
                .{ .pos = zlm.vec2(625, 100), .size = zlm.vec2(102, 48), .sprite = assets.tormenter_eye, .z = 0.4 },
            },
        } },
    }) catch @panic("failed to add tormenter");
}

export fn init() void {
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });
    assets.loadAssets();

    state.gfx.bind.vertex_buffers[0] = sg.makeBuffer(.{
        .usage = .STREAM,
        .size = 1024 * 64,
        .label = "quad-vertices",
    });
    state.gfx.bind.fs.samplers[0] = sg.makeSampler(.{});

    var desc: sg.ShaderDesc = .{};
    desc.attrs[0].name = "position";
    desc.attrs[1].name = "texcoord0";

    desc.fs.images[0] = .{ .image_type = ._2D, .used = true, .sample_type = .FLOAT };
    desc.fs.samplers[0] = .{ .used = true, .sampler_type = .FILTERING };
    desc.fs.image_sampler_pairs[0] = .{ .used = true, .image_slot = 0, .sampler_slot = 0, .glsl_name = "tex" };

    desc.vs.uniform_blocks[0].size = @sizeOf(f32) * 2;
    desc.vs.uniform_blocks[0].uniforms[0].name = "screenShake";
    desc.vs.uniform_blocks[0].uniforms[0].type = .FLOAT2;

    desc.vs.source = @embedFile("./shaders/vs.glsl");
    desc.fs.source = @embedFile("./shaders/fs.glsl");

    const shd = sg.makeShader(desc);

    var pip_desc: sg.PipelineDesc = .{
        .shader = shd,
        .depth = .{
            .compare = .LESS_EQUAL,
            .write_enabled = true,
        },
    };

    pip_desc.layout.attrs[0].format = .FLOAT3; // 12
    pip_desc.layout.attrs[1].format = .FLOAT2; // 8
    pip_desc.layout.attrs[2].format = .FLOAT4; // 16
    pip_desc.layout.attrs[3].format = .FLOAT; // 4, ensure that padding matches

    pip_desc.colors[0].blend = .{
        .enabled = true,
        .src_factor_rgb = .SRC_ALPHA,
        .dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
    };
    state.gfx.pip = sg.makePipeline(pip_desc);
    state.gfx.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0, .g = 0, .b = 0, .a = 1 },
    };

    state.gfx.projection = Mat4.createOrthogonal(0, sapp.widthf(), sapp.heightf(), 0, -1, 100);
    state.rand = std.Random.DefaultPrng.init(@bitCast(std.time.milliTimestamp()));

    resetGame();
}

fn flushQuadBatch() void {
    const gfx = &state.gfx;
    if (gfx.quad_batch_tex.id == 0 or gfx.quad_batch_index == 0) return;
    gfx.bind.vertex_buffer_offsets[0] = sg.appendBuffer(gfx.bind.vertex_buffers[0], .{ .ptr = &gfx.quad_batch, .size = @sizeOf(Vertex) * gfx.quad_batch_index });
    gfx.bind.fs.images[0] = gfx.quad_batch_tex;
    sg.applyBindings(gfx.bind);
    sg.draw(0, gfx.quad_batch_index, 1);
    gfx.quad_batch_index = 0;
}

fn pushQuad(mvp: Mat4, texture: sg.Image, tint: @Vector(4, f32), z: f32) void {
    if (texture.id != state.gfx.quad_batch_tex.id) flushQuadBatch();
    state.gfx.quad_batch_tex = texture;
    const tl = zlm.vec4(0, 0, 0, 1).transform(mvp);
    const tr = zlm.vec4(1, 0, 0, 1).transform(mvp);
    const bl = zlm.vec4(0, 1, 0, 1).transform(mvp);
    const br = zlm.vec4(1, 1, 0, 1).transform(mvp);
    // tri one
    state.gfx.quad_batch[state.gfx.quad_batch_index + 0] = Vertex{ .pos = .{ tl.x, tl.y, z }, .tex = .{ 0, 1 }, .tint = tint };
    state.gfx.quad_batch[state.gfx.quad_batch_index + 1] = Vertex{ .pos = .{ tr.x, tr.y, z }, .tex = .{ 1, 1 }, .tint = tint };
    state.gfx.quad_batch[state.gfx.quad_batch_index + 2] = Vertex{ .pos = .{ bl.x, bl.y, z }, .tex = .{ 0, 0 }, .tint = tint };

    // tri two
    state.gfx.quad_batch[state.gfx.quad_batch_index + 3] = Vertex{ .pos = .{ tr.x, tr.y, z }, .tex = .{ 1, 1 }, .tint = tint };
    state.gfx.quad_batch[state.gfx.quad_batch_index + 4] = Vertex{ .pos = .{ bl.x, bl.y, z }, .tex = .{ 0, 0 }, .tint = tint };
    state.gfx.quad_batch[state.gfx.quad_batch_index + 5] = Vertex{ .pos = .{ br.x, br.y, z }, .tex = .{ 1, 0 }, .tint = tint };

    state.gfx.quad_batch_index += 6;
}

const WHITE = @Vector(4, f32){ 1, 1, 1, 1 };

fn lerp(start: f32, end: f32, t: f32) f32 {
    return start + (end - start) * t;
}

export fn frame() void {
    const dt: f32 = @floatCast(sapp.frameDuration());

    sg.beginPass(.{ .action = state.gfx.pass_action, .swapchain = sglue.swapchain() });
    sg.applyPipeline(state.gfx.pip);

    {
        state.gfx.screen_shake_duration -= dt;
        if (state.gfx.screen_shake_duration <= 0) state.gfx.screen_shake = 0;
        const rand = state.rand.random();
        const x = rand.float(f32) * state.gfx.screen_shake * 2 - state.gfx.screen_shake;
        const y = rand.float(f32) * state.gfx.screen_shake * 2 - state.gfx.screen_shake;
        sg.applyUniforms(.VS, 0, sg.asRange(&.{ x / 800, y / 600 }));
    }

    if (state.game.score >= 4800 and state.game.tormenter == .unspawned) {
        spawnTormenter();
        state.game.tormenter = .alive;
    }
    // update ship
    var ship_actor = &state.game.ship.actor;
    const accel = state.game.ship.accel;
    if (ship_actor.active) {
        if (state.input.up) {
            ship_actor.vel.y -= accel * dt;
        }

        if (state.input.down) {
            ship_actor.vel.y += accel * dt;
        }

        if (state.input.left) {
            ship_actor.vel.x -= accel * dt;
        }

        if (state.input.right) {
            ship_actor.vel.x += accel * dt;
        }

        if (state.input.shoot) {
            state.game.ship.shoot(dt) catch @panic("failed to append shot to hazards");
        }
    }
    {
        state.game.ship.respawn -= dt;
        if (state.game.ship.respawn <= 0 and !ship_actor.active) {
            ship_actor.active = true;
            ship_actor.pos = zlm.vec2(400 - ship_actor.size.x, 400);
        }
        ship_actor.update(dt);
        ship_actor.draw(WHITE);
    }

    {
        var i = state.game.aliens.items.len;
        while (i > 0) {
            i -= 1;
            const alien = &state.game.aliens.items[i];
            alien.update(dt);
            alien.damage_tint -= dt * 4;
            alien.draw();
        }
    }

    {
        var i = state.game.hazards.items.len;
        outer: while (i > 0) {
            i -= 1;
            const hazard = &state.game.hazards.items[i];
            const update_res = hazard.update(dt);
            if (update_res.remove_self) {
                _ = state.game.hazards.swapRemove(i);
                continue;
            }

            // check for collisions
            if (hazard.friendly) {
                var j = state.game.aliens.items.len;
                while (j > 0) {
                    j -= 1;
                    const alien = &state.game.aliens.items[j];
                    if (hazard.actor.collides(alien.actor)) {
                        shake(2, 0.1);
                        const res = alien.onCollide(hazard);
                        if (res.remove_self) {
                            _ = state.game.aliens.swapRemove(j);
                            state.game.score += switch (alien.specific) {
                                .basic => 100,
                                .tormenter => 1000,
                            };
                        }
                        if (res.remove_hazard) {
                            _ = state.game.hazards.swapRemove(i);

                            continue :outer;
                        }
                    }
                }
            } else {
                if (ship_actor.active and hazard.actor.collides(ship_actor.*)) {
                    state.game.ship.respawn = 3;
                    ship_actor.active = false;
                }
            }

            hazard.actor.draw(WHITE);
        }
    }

    flushQuadBatch();

    sg.endPass();
    sg.commit();
}

export fn input(ev: ?*const sapp.Event) void {
    const event = ev.?;
    if (event.type == .KEY_DOWN or event.type == .KEY_UP) {
        const key_pressed = event.type == .KEY_DOWN;
        switch (event.key_code) {
            .W, .UP => state.input.up = key_pressed,
            .S, .DOWN => state.input.down = key_pressed,
            .A, .LEFT => state.input.left = key_pressed,
            .D, .RIGHT => state.input.right = key_pressed,
            .SPACE => state.input.shoot = key_pressed,
            // .ESCAPE => state.input.esc = key_pressed,
            else => {},
        }
    }
}

export fn cleanup() void {
    sg.shutdown();
    zstbi.deinit();
}

pub fn main() !void {
    _ = std.debug.print("{any}", .{hex("#ffffff")});
    zstbi.init(gpa.allocator());
    zstbi.setFlipVerticallyOnLoad(true);

    sapp.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .event_cb = input,
        .cleanup_cb = cleanup,
        .width = 800,
        .height = 600,
    });
}
