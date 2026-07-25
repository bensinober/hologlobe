const std = @import("std");

const mem = std.mem;
const fs = std.fs;
const posix = std.posix;

// for http server
const http = std.http;
const index_html = @embedFile("www/index.html");
const script_js = @embedFile("www/script.js");

// the rest
const gpiod = @import("gpiod.zig");
const ws2811 = @import("ws2811.zig");
const spi = @import("spi.zig");
const img = @import("img.zig");

const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;
const time = std.time;

const HALL_PIN = 23; // TODO: add hall sensor
const LEDSTRIP_COLS = 50; // img width (=length of one frame, and one strip)
const LEDSTRIP_ROWS = 100; //img height
const LEDSTRIP_LENGTH = LEDSTRIP_COLS * 2; // each led strip is two joined * 50
const LEDSTRIP_PIN_A = 18; // GPIO18 (12)
const LEDSTRIP_PIN_B = 13; // GPIO13 (33)
//const LEDSTRIP_PIN = 28; // =18 = GPIO4_D4 = pin 3*8+4 = 28

const BTN_A_PIN = 17; // pin 13 -> GPIO17
//const BTN_B_PIN = 18; // pin 15 -> GPIO18
const ROT_A_PIN = 5; // pin 29 -> GPIO5
const ROT_B_PIN = 6; // pin 31 -> GPIO6

// GLOBALS LED Mode
pub const LEDMode = enum(u8) {
    IDLE,
    CALIBRATE,
    DRAW,
    RUNONCE,
    ANIMATION,
    _,

    pub fn enum2str(self: LEDMode) []u8 {
        return std.meta.fields(?LEDMode)[self];
    }
    pub fn str2enum(str: []const u8) ?LEDMode {
        return std.meta.stringToEnum(LEDMode, str) orelse LEDMode.IDLE;
    }
};

const ControlError = error{
    GpioChipFail,
};

var spiBus: spi.Bus = undefined;

// initial mode
var ledMode = LEDMode.IDLE;
var lastLedMode = LEDMode.IDLE;

pub const Server = struct {
    allocator: Allocator,
    io: std.Io,
    listener: std.Io.net.Server,
    ledController: *LedControl,
    // Add other fields as needed, e.g., for routing, database connections, etc.

    pub fn init(allocator: std.mem.Allocator, io: std.Io, port: u16, ledController: *LedControl) !Server {
        const address = try std.Io.net.IpAddress.parse("0.0.0.0", port);
        const listener = try address.listen(io, .{ .reuse_address = true });
        std.debug.print("Listening on {d}\n", .{port});

        return Server{
            .allocator = allocator,
            .io = io,
            .listener = listener,
            .ledController = ledController,
        };
    }

    pub fn deinit(self: *Server) void {
        self.listener.deinit(self.io);
    }

    pub fn serve(self: *Server) !void {
        while (true) {
            try self.handleConnection(try self.listener.accept(self.io));
        }
    }

    // Request handler function (example)
    pub fn handleConnection(self: *Server, conn: std.Io.net.Stream) !void {
        //defer conn.stream.close();
        var recvBuf: [82984]u8 = undefined; // img raw is 50 x 100 x 4 = 20000 bytes
        var sendBuf: [4096]u8 = undefined;
        var reader = conn.reader(self.io, &recvBuf);
        var writer = conn.writer(self.io, &sendBuf);

        var httpServer = std.http.Server.init(&reader.interface, &writer.interface);
        var req = try httpServer.receiveHead();
        std.debug.print("Received request: {any}\n", .{req});

        // TODO: remove
        var it = req.iterateHeaders();
        while (it.next()) |header| {
            std.debug.print("HEADER: {s} - VAL: {s}\n", .{ header.name, header.value });
        }
        // https://github.com/ziglang/zig/issues/25017
        // if body content_length is not null
        req.head.keep_alive = false;

        // assert(request.head.transfer_encoding != .none or request.head.content_length != null);
        if (req.head.method == .GET and std.mem.eql(u8, req.head.target, "/")) {
            //var response_headers = std.http.Header{};
            //response_headers.content_type = "text/html";
            const indexLen = try std.fmt.allocPrint(self.allocator, "{d}", .{index_html.len});
            try req.respond(index_html, .{
                .status = .ok,
                .extra_headers = &.{
                    http.Header{ .name = "Content-Type", .value = "text/html" },
                    http.Header{ .name = "Content-Length", .value = indexLen },
                },
            });
        } else if (std.mem.eql(u8, req.head.target, "/script.js")) {
            const scriptLen = try std.fmt.allocPrint(self.allocator, "{d}", .{script_js.len});
            try req.respond(script_js, .{
                .status = .ok,
                .extra_headers = &.{
                    http.Header{ .name = "Content-Type", .value = "text/javascript" },
                    http.Header{ .name = "Content-Length", .value = scriptLen },
                },
            });
            // LED CONTROL
        } else if (req.head.method == .PUT and std.mem.eql(u8, req.head.target, "/cycleColours")) {
            try self.ledController.cycleColours();
            try req.respond("CYCLE", .{ .status = .ok, .transfer_encoding = .chunked });
        } else if (req.head.method == .PUT and std.mem.eql(u8, req.head.target, "/cycleColumns")) {
            try self.ledController.cycleColumns([4]u8{0, 0xff, 0, 0});
            try req.respond("CYCLE", .{ .status = .ok, .transfer_encoding = .chunked });
        } else if (req.head.method == .GET and std.mem.startsWith(u8, req.head.target, "/setMode")) {
            var paths = std.mem.splitScalar(u8, req.head.target, '/');
            var i: usize = 0;
            while (paths.next()) |p| {
                if (i == 2) {
                    const mode = LEDMode.str2enum(p);
                    std.debug.print("NEW LedMode {any}!\n", .{mode});
                    ledMode = mode.?;
                }
                i += 1;
            }
            try req.respond("OK", .{ .status = .ok, .transfer_encoding = .chunked });
        } else if (req.head.method == .GET and std.mem.eql(u8, req.head.target, "/getMode")) {
            try req.respond(@tagName(ledMode), .{ .status = .ok, .transfer_encoding = .chunked });
        } else if (req.head.method == .PUT and std.mem.eql(u8, req.head.target, "/firstRow")) {
            try self.ledController.runFirstRow();
            try req.respond("TEST", .{ .status = .ok, .transfer_encoding = .chunked });
        } else if (req.head.method == .POST and std.mem.eql(u8, req.head.target, "/uploadRawImg")) {
            var len: usize = 0;
            if (req.head.content_length) |contLen| {
                len = @intCast(contLen);
            }
            const body = try reader.interface.take(len);
            std.debug.print("UPLOAD body: {any}\n", .{reader});
            self.ledController.setImg(body) catch |err| {
                std.debug.print("Error uploading image: {}\n", .{err});
                try req.respond("Error uploading image!", .{ .status = .internal_server_error });
                return err;
            };
            // const imgMatrix = LedControl.imgbytes2matrix(body) catch |err| {
            //     std.debug.print("Error: {}\n", .{err});
            //     try req.respond("NO GO!", .{err});
            // };
            // self.ledController.imgMatrix = &imgMatrix;
            try req.respond("OK", .{});
        } else {
            try req.respond("Not Found", .{ .status = .not_found });
        }

        // Example: Respond to a GET request
        // if (request.method == .GET) {
        //     const response_body = "Hello from Zig!";
        //     try request.respond(response_body, .{});
        // } else {
        //     // Handle other methods or send an error response
        //     try request.respond("Method Not Allowed", .{ .status = .method_not_allowed });
        // }
        // if (std.mem.eql(u8, req.method.toSlice(), "GET") and std.mem.eql(u8, req.target.toSlice(), "/")) {
        //     res.transfer_encoding.setChunked();
        //     try res.sendHeaders();
        //     _ = try res.writer().write("Hello, Zig HTTP Server!");
        // } else {
        //     res.status = .not_found;
        //     res.transfer_encoding.setChunked();
        //     try res.sendHeaders();
        //     _ = try res.writer().write("404 Not Found");
        // }
        conn.close(self.io);
    }

};

const ImageMat = struct {
    mat: [LEDSTRIP_ROWS][LEDSTRIP_COLS][4]u8,
};

pub const LedControl = struct {
    const Self = @This();

    ptr: [*c]ws2811.ws2811_t,
    io: std.Io,
    calibrationMatrix: ImageMat,
    imgMatrix: ImageMat,
    frameBuf: [2][LEDSTRIP_LENGTH][4]u8, // channel 0 + 1
    allocator: Allocator,
    mutex: std.Io.Mutex,

    pub fn init(allocator: Allocator, io: std.Io, ledstrip: [*c]ws2811.ws2811_t) !Self {
        const frameBuf: [2][LEDSTRIP_LENGTH][4]u8 = undefined;
        return Self{
            .ptr = ledstrip,
            .io = io,
            .calibrationMatrix = undefined,
            .imgMatrix = undefined,
            .frameBuf = frameBuf,
            .allocator = allocator,
            .mutex = std.Io.Mutex.init,
        };
    }
    pub fn deinit(self: *Self) void {
        if (@import("builtin").target.cpu.arch != std.Target.Cpu.Arch.x86_64) {
            defer ws2811.ws2811_fini(self.ptr);
        }
    }
    pub fn clearBuffer(_: *Self) void {
        // TODO loop and std.mem.set(u8, buffer[0..], 0);
    }

    pub fn setInitialImg(self: *Self) !void {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        const mat = try imgbytes2matrix(&img.DATA);
        const imageMat: ImageMat = .{ .mat = mat };
        self.calibrationMatrix = imageMat;
    }

    pub fn setImg(self: *Self, imageBytes: []u8) !void {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        //const copy = try self.allocator.alloc(u8, imageBytes.len);
        //@memcpy(copy[0..], imageBytes);
        const mat = try imgbytes2matrix(imageBytes);
        const imageMat: ImageMat = .{ .mat = mat };
        self.imgMatrix = imageMat;
        std.debug.print("mat: {any}\n", .{mat});
    }

    // rgba -> grba
    // pixel is rgba, strip is agrb big endian
    pub fn setPixel(self: *Self, chan: usize, ledIdx: usize, colour: [4]u8) !void {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        self.frameBuf[chan][ledIdx][0] = colour[3];
        self.frameBuf[chan][ledIdx][1] = colour[0];
        self.frameBuf[chan][ledIdx][2] = colour[1];
        self.frameBuf[chan][ledIdx][3] = colour[2];
        //std.debug.print("colour: {x}, ledIdx: {d}\n", .{ colour, ledIdx });
    }

    ///////  Testing!
    pub fn renderFirstRow(self: *Self) !void {
        const mat = self.imgMatrix;
        std.debug.print("row 0: {any}\n", .{mat.mat[0]});
        for (0..LEDSTRIP_COLS) |idx| {
            const colour = mat.mat[0][idx];
            try self.setPixel(0, idx, colour);
            std.debug.print("colour: {any}, ledIdx: {d}\n", .{ colour, idx });
        }
        if (@import("builtin").target.cpu.arch != std.Target.Cpu.Arch.x86_64) {
            try self.show();
        }
        //try self.io.sleep(std.Io.Duration.fromMicroseconds(350), .real); // sleep 350us to balance frame rate of 5Hz
    }

    pub fn runFirstRow(self: *Self) !void {
        const start = std.Io.Clock.awake.now(self.io);
        try self.renderFirstRow();
        var elapsed = start.untilNow(self.io, .awake);
        const ns = elapsed.toNanoseconds();

        std.debug.print("ns spent on first line render: {}\n", .{ns});
        try self.io.sleep(std.Io.Duration.fromMilliseconds(1), .real);
    }

    // Two strips split in half generated for each frame
    // render img row by row, split in half, reverse second half, as strip is one piece continuing over middle
    // source image is 50x100 24bit
    pub fn renderImg(self: *Self) !void {
        const mat = self.imgMatrix;
        const half = LEDSTRIP_ROWS / 2;
        const quarter = LEDSTRIP_ROWS / 4; // split rows in four, two for each strip
        for (0..quarter) |i| {
            for (0..LEDSTRIP_COLS) |j| {
                // channel 0:
                try self.setPixel(0, j, mat.mat[i][j]);
                const backPixelA = mat.mat[i + quarter][LEDSTRIP_COLS - 1 - j]; // reversed
                try self.setPixel(0, LEDSTRIP_COLS + j, backPixelA);
                // channel 1:
                try self.setPixel(1, j, mat.mat[i + half][j]);
                const backPixelB = mat.mat[i + quarter + half][LEDSTRIP_COLS - 1 - j]; // reversed
                try self.setPixel(1, LEDSTRIP_COLS + j, backPixelB);
            }
            if (@import("builtin").target.cpu.arch != std.Target.Cpu.Arch.x86_64) {
               try self.show();
               // _ = ws2811.ws2811_render(self.ptr); // show row
            }
            //try self.io.sleep(std.Io.Duration.fromMicroseconds(350), .real); // sleep 350us to balance frame rate of 5Hz
        }
    }

    // render interlaced, 100x200 split i half, alternating abab
    // pub fn renderImg(self: *Self) void {
    //     const mat = self.imgMatrix;
    //     const half = LEDSTRIP_ROWS / 2; // split rows in two, one for each strip
    //     for (0..half) |i| {
    //         for (0..LEDSTRIP_COLS) |j| {
    //             const ledIdx: usize = @divFloor(j, 2);
    //             if (i % 2 == 0) {
    //                 if (j % 2 == 0) {
    //                     self.setPixel(0, ledIdx, mat.mat[i][j]);
    //                 } else {
    //                     self.setPixel(1, ledIdx, mat.mat[i + half][j]);
    //                 }
    //             } else {
    //                 if (j % 2 == 0) {
    //                     self.setPixel(1, ledIdx, mat.mat[i][j]);
    //                 } else {
    //                     self.setPixel(0, ledIdx, mat.mat[i + half][j]);
    //                 }
    //             }
    //         }
    //         if (@import("builtin").target.cpu.arch != std.Target.Cpu.Arch.x86_64) {
    //             _ = ws2811.ws2811_render(self.ptr); // show row
    //         }
    //         //try self.io.sleep(std.Io.Duration.fromMicroseconds(350), .real); // sleep 350us to balance frame rate of 5Hz
    //     }
    // }

    pub fn renderCalibration(self: *Self) !void {
        const mat = self.calibrationMatrix;
        const half = LEDSTRIP_ROWS / 2;
        const quarter = LEDSTRIP_ROWS / 4; // split rows in four, two for each strip
        for (0..quarter) |i| {
            for (0..LEDSTRIP_COLS) |j| {
                // channel 0:
                try self.setPixel(0, j, mat.mat[i][j]);
                const backPixelA = mat.mat[i + quarter][LEDSTRIP_COLS - 1 - j]; // reversed
                try self.setPixel(0, LEDSTRIP_COLS + j, backPixelA);
                // channel 1:
                try self.setPixel(1, j, mat.mat[i + half][j]);
                const backPixelB = mat.mat[i + quarter + half][LEDSTRIP_COLS - 1 - j]; // reversed
                try self.setPixel(1, LEDSTRIP_COLS + j, backPixelB);
            }
            if (@import("builtin").target.cpu.arch != std.Target.Cpu.Arch.x86_64) {
               try self.show();
               // _ = ws2811.ws2811_render(self.ptr); // show row
            }
            //try self.io.sleep(std.Io.Duration.fromMicroseconds(350), .real); // sleep 350us to balance frame rate of 5Hz
        }
    }

    // both channels
    pub fn lightAllLeds(self: *Self, col: [4]u8) !void {
        if (@import("builtin").target.cpu.arch != std.Target.Cpu.Arch.x86_64) {
            var i: usize = 0;
            while (i < LEDSTRIP_LENGTH) : (i += 1) {
                try self.setPixel(0, i, col);
                try self.setPixel(1, i, col);
                //self.frameBuf[i] = col;
            }
            try self.show();
        }
    }

    // Startup, blink red, green and blue
    pub fn cycleColours(self: *Self) !void {
        var start: std.Io.Timestamp = undefined;

        start = std.Io.Clock.awake.now(self.io);
        try self.lightAllLeds([4]u8{0xff, 0, 0, 0});
        var elapsed = start.untilNow(self.io, .awake);
        var ns = elapsed.toNanoseconds();
        std.debug.print("ns spent on red cycle: {}\n", .{ns});

        try self.io.sleep(std.Io.Duration.fromMilliseconds(500), .real);

        start = std.Io.Clock.awake.now(self.io);
        try self.lightAllLeds([4]u8{0, 0xff, 0, 0});
        elapsed = start.untilNow(self.io, .awake);
        ns = elapsed.toNanoseconds();
        std.debug.print("ns spent on green cycle: {}\n", .{ns});

        try self.io.sleep(std.Io.Duration.fromMilliseconds(500), .real);

        start = std.Io.Clock.awake.now(self.io);
        try self.lightAllLeds([4]u8{0, 0, 0xff, 0});
        elapsed = start.untilNow(self.io, .awake);
        ns = elapsed.toNanoseconds();
        std.debug.print("ns spent on blue cycle: {}\n", .{ns});

        try self.io.sleep(std.Io.Duration.fromMilliseconds(500), .real);

        try self.lightAllLeds([4]u8{0, 0, 0, 0});

        try self.io.sleep(std.Io.Duration.fromMilliseconds(1000), .real);
    }

    pub fn runOnce(self: *Self) !void {
        const start = try std.time.Instant.now();
        try self.renderImg();
        const end = try std.time.Instant.now();
        std.debug.print("ns spent on full render: {}\n", .{end.since(start)});
        try self.io.sleep(std.Io.Duration.fromMilliseconds(1), .real);
    }

    pub fn cycleColumns(self: *Self, col: [4]u8) !void {
        if (@import("builtin").target.cpu.arch != std.Target.Cpu.Arch.x86_64) {
            for (0..LEDSTRIP_LENGTH) |x| {
                try self.setPixel(0, x, col);
                try self.setPixel(1, x, col);
                try self.show();
                try self.io.sleep(std.Io.Duration.fromMilliseconds(10), .real);
                try self.setPixel(0, x, [4]u8{0, 0, 0, 0});
                try self.setPixel(1, x, [4]u8{0, 0, 0, 0});
                try self.show();
            }
        }
    }

    pub fn u32ToU8Bytes(value: u32) [4]u8 {
        var buf: [4]u8 = undefined;
        std.mem.writeInt(u32, &buf, value, .big);
        return buf;
    }

    // event loop running in thread
    pub fn runMatrix(self: *Self) !void {
        while (true) {
            switch (ledMode) {
                .IDLE => {
                    try self.io.sleep(std.Io.Duration.fromMilliseconds(1), .real); // to ease cpu
                },
                .CALIBRATE => {
                    try self.renderCalibration();
                },
                .DRAW => {
                    try self.io.sleep(std.Io.Duration.fromMilliseconds(1), .real); // to ease cpu
                },
                .RUNONCE => {
                    try self.renderImg();
                    ledMode = LEDMode.IDLE;
                },
                .ANIMATION => {
                    const start = std.Io.Clock.awake.now(self.io);
                    try self.renderImg();
                    var elapsed = start.untilNow(self.io, .awake);
                    const ns = elapsed.toNanoseconds();
                    std.debug.print("ns spent on full render: {}\n", .{ns});
                },
                else => {
                    std.debug.print("UNKNOWN STATE", .{});
                },
            }
        }
    }

    // send entire frame
    pub fn show(self: *Self) !void {
        //std.debug.print("FRAME: {any}", .{self.frameBuf});
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        for (0..LEDSTRIP_LENGTH) |idx| {
            const colourA = self.frameBuf[0][idx];
            const valueA: u32 = (@as(u32, colourA[0]) << 24) | (@as(u32, colourA[1]) << 16) | (@as(u32, colourA[2]) << 8) | @as(u32, colourA[3]);
            const colourB = self.frameBuf[1][idx];
            const valueB: u32 = (@as(u32, colourB[0]) << 24) | (@as(u32, colourB[1]) << 16) | (@as(u32, colourB[2]) << 8) | @as(u32, colourB[3]);
            if (@import("builtin").target.cpu.arch != std.Target.Cpu.Arch.x86_64) {
              self.ptr.*.channel[0][0].leds[idx] = valueA;
              self.ptr.*.channel[0][1].leds[idx] = valueB;
            } else {
              std.debug.print("colourA: {x}, chan: {d}, ledIdx: {d}, bigend: 0x{x:0>8}\n", .{ colourA, 0, idx, valueA });
              std.debug.print("colourB: {x}, chan: {d}, ledIdx: {d}, bigend: 0x{x:0>8}\n", .{ colourB, 0, idx, valueB });
            }
        }
         _ = ws2811.ws2811_render(self.ptr);
    }


    // transform png data [][4]u8 to led matrix pixel vector (mat[row][col]pixel) [rows][cols][4]u8 prepared for led strip length
    // NB : image data sent over wire starts top left, we need to set pixels in same order
    pub fn imgbytes2matrix(bytes: []const u8) ![LEDSTRIP_ROWS][LEDSTRIP_COLS][4]u8 {
        var reader = std.Io.Reader.fixed(bytes);
        var mat: [LEDSTRIP_ROWS][LEDSTRIP_COLS][4]u8 = undefined;
        var pixel: [4]u8 = undefined; // in littleendian format rgba
        for (0..LEDSTRIP_ROWS) |row| {
            for (0..LEDSTRIP_COLS) |col| {
                try reader.readSliceAll(pixel[0..]); // read to buffer is full
                mat[row][col] = pixel;
            }
        }
        return mat;
    }

};

// Get WIFI IP address by fake UDP connection
pub fn getLocalAddress(io: std.Io, alloc: Allocator) ![]const u8 {
    const local = try std.Io.net.IpAddress.parse("0.0.0.0", 0);
    const remote = try std.Io.net.IpAddress.parse("1.1.1.1", 0);
    var socket = try local.bind(io, .{ .mode = .dgram, .protocol = .udp });
    defer socket.close(io);
    const conn = try remote.connect(io, .{ .mode = .dgram });
    const address = conn.socket.address;
    const out = try std.fmt.allocPrint(alloc, "{f}", .{address});
    return out;
}

pub fn main(init: std.process.Init) !void {
    // init IO
    const allocator = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(allocator);

    for (args) |arg| {
        std.log.info("Argument: {s}", .{arg});
    }
    const arch = @import("builtin").target.cpu.arch;
    // Prints to stderr, shortcut based on `std.io.getStdErr()`
    std.debug.print("Testing zig for hologlobe Magic!.\n", .{});

    const addr = try getLocalAddress(io, allocator);
    std.debug.print("hologlobe IP addr: {s}\n", .{addr});

    // LEDSTRIP INIT
    var ledstrip: ws2811.ws2811_t = undefined;
    if (arch != std.Target.Cpu.Arch.x86_64) {
        // GPIO INIT
        const chp = gpiod.gpiod_chip_open("/dev/gpiochip0");
        if (chp == null) {
            std.debug.print("failed opening gpiochip0 for Control!\n", .{});
            return ControlError.GpioChipFail;
        }
        //defer gpiod.gpiod_chip_close(chp);

        // ws281x
        // const ledChip = gpiod.gpiod_chip_open_by_name("gpiochip4");
        // var ledCtrl = ws281x.WS281x.init(ledChip, LEDSTRIP_PINA);
        // defer ledCtrl.deinit();
        // ledCtrl.showColor(0xff, 0xff, 0xa0);
        // ledCtrl.sendReset();

        // ws2811 init
        ledstrip = ws2811.ws2811_t{
            .render_wait_time = 0,
            .device = null,
            .rpi_hw = null,
            .freq = 800000,
            .dmanum = 10,
            .channel = .{
                .{
                    .gpionum = LEDSTRIP_PIN_A,
                    .invert = 0,
                    .count = LEDSTRIP_LENGTH,
                    .strip_type = ws2811.WS2811_STRIP_GRB,
                    .leds = null,
                    .brightness = 50,
                    .wshift = 0x00,
                    .rshift = 0x00,
                    .gshift = 0x00,
                    .bshift = 0x00,
                    .gamma = null,
                },
                .{
                    .gpionum = LEDSTRIP_PIN_B,
                    .invert = 0,
                    .count = LEDSTRIP_LENGTH,
                    .strip_type = ws2811.WS2811_STRIP_GRB,
                    .leds = null,
                    .brightness = 50,
                    .wshift = 0x00,
                    .rshift = 0x00,
                    .gshift = 0x00,
                    .bshift = 0x00,
                    .gamma = null,
                },
            },
        };
        _ = ws2811.ws2811_init(&ledstrip);

    }
    // we need to hold GPIO and Display allocated until exit

    var ledController = try LedControl.init(allocator, io, &ledstrip);
    try ledController.setInitialImg();
    defer ledController.deinit();

    // spawn ledrunner in separate thread
    const ledThread = try std.Thread.spawn(.{}, LedControl.runMatrix, .{&ledController});
    ledThread.detach();

    var server = try Server.init(allocator, io, 8765, &ledController);
    defer server.deinit();

    try server.serve();
}
