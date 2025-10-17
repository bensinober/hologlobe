const std = @import("std");

const mem = std.mem;
const fs = std.fs;
const posix = std.posix;

// for http server
const net = std.net;
const http = std.http;
const index_html = @embedFile("www/index.html");
const script_js = @embedFile("www/script.js");

// the rest
const gpiod = @import("gpiod.zig");
const ssd1305 = @import("ssd1305.zig");
//const ws281x = @import("ws281x.zig");
const ws2811 = @import("ws2811.zig");
const img = @import("img.zig"); // TODO: use API to upload/convert images instead

const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;
const time = std.time;

var display: ssd1305.Display = undefined;
var spiBus: ssd1305.SpiBus = undefined;

const HALL_PIN = 23; // TODO: add hall sensor
const LEDSTRIP_COLS = 50; // img width
const LEDSTRIP_ROWS = 100; //img height
const LEDSTRIP_PIN_A = 18; // GPIO18 (12)
const LEDSTRIP_PIN_B = 13; // GPIO13 (33)
//const LEDSTRIP_PIN = 28; // =18 = GPIO4_D4 = pin 3*8+4 = 28

const BTN_A_PIN = 17; // pin 13 -> GPIO17
//const BTN_B_PIN = 18; // pin 15 -> GPIO18
const ROT_A_PIN = 5; // pin 29 -> GPIO5
const ROT_B_PIN = 6; // pin 31 -> GPIO6

pub const Server = struct {
    allocator: Allocator,
    listener: std.net.Server,
    controller: Control,
    ledController: *LedControl,
    // Add other fields as needed, e.g., for routing, database connections, etc.

    pub fn init(allocator: std.mem.Allocator, port: u16, controller: Control, ledController: *LedControl) !Server {
        const address = try std.net.Address.parseIp("0.0.0.0", port);
        const listener = try address.listen(.{ .reuse_address = true });
        std.debug.print("Listening on {d}\n", .{port});

        return Server{
            .allocator = allocator,
            .listener = listener,
            .controller = controller,
            .ledController = ledController,
        };
    }

    pub fn deinit(self: *Server) void {
        self.listener.deinit();
    }

    pub fn serve(self: *Server) !void {
        while (true) {
            try self.handleConnection(try self.listener.accept());
        }
    }

    // Request handler function (example)
    pub fn handleConnection(self: *Server, conn: net.Server.Connection) !void {
        //defer conn.stream.close();
        var recvBuf: [21504]u8 = undefined; // img raw is 50 x 100 x 4 = 20000 bytes
        var sendBuf: [4096]u8 = undefined;
        var reader = conn.stream.reader(&recvBuf);
        var writer = conn.stream.writer(&sendBuf);
        var httpServer = std.http.Server.init(reader.interface(), &writer.interface);
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
            self.ledController.cycleColours();
            try req.respond("CYCLE", .{ .status = .ok, .transfer_encoding = .chunked });
        } else if (req.head.method == .PUT and std.mem.eql(u8, req.head.target, "/cycleColumns")) {
            self.ledController.cycleColumns(0xff0000);
            try req.respond("CYCLE", .{ .status = .ok, .transfer_encoding = .chunked });
        } else if (req.head.method == .PUT and std.mem.eql(u8, req.head.target, "/toggleActive")) {
            self.ledController.toggleActive();
            const response = std.fmt.allocPrint(self.allocator, "NEW STATE: {any}\n", .{self.ledController.activeMatrix}) catch @panic("Failed to format status line");
            try req.respond(response, .{ .status = .ok, .transfer_encoding = .chunked });
        } else if (req.head.method == .PUT and std.mem.eql(u8, req.head.target, "/firstRow")) {
            try self.ledController.runFirstRow();
            try req.respond("TEST", .{ .status = .ok, .transfer_encoding = .chunked });
        } else if (req.head.method == .PUT and std.mem.eql(u8, req.head.target, "/runOnce")) {
            try self.ledController.runOnce();
            const response = std.fmt.allocPrint(self.allocator, "NEW STATE: {any}\n", .{self.ledController.activeMatrix}) catch @panic("Failed to format status line");
            try req.respond(response, .{ .status = .ok, .transfer_encoding = .chunked });
        } else if (req.head.method == .PUT and std.mem.eql(u8, req.head.target, "/start")) {
            const thread = try std.Thread.spawn(.{}, LedControl.runMatrix, .{self.ledController});
            thread.detach();
            const response = std.fmt.allocPrint(self.allocator, "matrix started in thread: {any}\n", .{thread}) catch @panic("Failed to set matrix");
            try req.respond(response, .{});
            // Raw image data uploaded from js clampedUint8Array, can set LedControl Matrix directly
        } else if (req.head.method == .POST and std.mem.eql(u8, req.head.target, "/uploadRawImg")) {
            var len: usize = 0;
            if (req.head.content_length) |contLen| {
                len = @intCast(contLen);
            }
            const body = try reader.interface().take(len);
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
        conn.stream.close();
    }

    fn sendFile(writer: std.io.Writer, filename: []const u8) !void {
        const file = try std.fs.cwd().openFile(filename, .{});
        defer file.close();

        var buffer: [1024]u8 = undefined;
        while (true) {
            const read_bytes = try file.read(buffer[0..]);
            if (read_bytes.len == 0) break;
            try writer.writeAll(read_bytes);
        }
    }
};

pub const Control = struct {
    const Self = @This();

    chip: ?*gpiod.struct_gpiod_chip,
    led: ?*gpiod.struct_gpiod_line,
    btnA: ?*gpiod.struct_gpiod_line,
    rotA: ?*gpiod.struct_gpiod_line,
    rotB: ?*gpiod.struct_gpiod_line,

    pub fn init(chip: ?*gpiod.struct_gpiod_chip) Self {
        // led
        const ledLine = gpiod.gpiod_chip_get_line(chip, HALL_PIN); // gpiod_chip_get_lines for bulk
        const baLine = gpiod.gpiod_chip_get_line(chip, BTN_A_PIN);
        const raLine = gpiod.gpiod_chip_get_line(chip, ROT_A_PIN);
        const rbLine = gpiod.gpiod_chip_get_line(chip, ROT_B_PIN);
        _ = gpiod.gpiod_line_request_output(ledLine, "ledblink", 0);
        const buttonConfig = &gpiod.gpiod_line_request_config{
            .consumer = "hologlobe",
            .request_type = gpiod.GPIOD_LINE_REQUEST_DIRECTION_INPUT,
            .flags = gpiod.GPIOD_LINE_REQUEST_FLAG_BIAS_PULL_UP,
        };
        _ = gpiod.gpiod_line_request(baLine, buttonConfig, 1);
        //_ = gpiod.gpiod_line_request_falling_edge_events(baLine, "buttons");
        _ = gpiod.gpiod_line_request_input(raLine, "rota");
        _ = gpiod.gpiod_line_request_input(rbLine, "rotb");
        return Self{
            .chip = chip,
            .led = ledLine,
            .btnA = baLine,
            .rotA = raLine,
            .rotB = rbLine,
        };
    }
    pub fn deinit(self: Self) void {
        _ = gpiod.gpiod_line_release(self.led);
    }

    pub fn led_blink(self: Self) void {
        std.debug.print("blinking led\n", .{});
        _ = gpiod.gpiod_line_set_value(self.led, 1);
        std.Thread.sleep(200 * 1000 * 1000); // 200ms
        _ = gpiod.gpiod_line_set_value(self.led, 0);
    }

    // TOOD: bulk register buttons and listen for falling edge
    pub fn pollButtonEvents(self: *Self) !void {
        var press: u3 = 0;
        const ba = gpiod.gpiod_line_get_value(self.btnA);
        if (ba == 0) {
            press = 1;
        }
        if (press > 0) {
            self.led_blink();

            switch (press) {
                1 => {
                    //try synth.selectPrevSoundFont();
                },
                else => {
                    std.debug.print("Unknown button\n", .{});
                },
            }
        }
    }
};

const ImageMat = struct {
    mat: [LEDSTRIP_ROWS][LEDSTRIP_COLS][4]u8,
};

pub const LedControl = struct {
    const Self = @This();

    ptr: [*c]ws2811.ws2811_t,
    activeMatrix: bool,
    imgMatrix: ImageMat,
    allocator: Allocator,
    mutex: std.Thread.Mutex,

    pub fn init(allocator: Allocator, ledstrip: [*c]ws2811.ws2811_t) !Self {
        return Self{
            .ptr = ledstrip,
            .activeMatrix = true,
            .imgMatrix = undefined,
            .allocator = allocator,
            .mutex = std.Thread.Mutex{},
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
        self.mutex.lock();
        defer self.mutex.unlock();
        const mat = try imgbytes2matrix(&img.DATA);
        const imageMat: ImageMat = .{ .mat = mat };
        self.imgMatrix = imageMat;
    }

    pub fn setImg(self: *Self, imageBytes: []u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        //const copy = try self.allocator.alloc(u8, imageBytes.len);
        //@memcpy(copy[0..], imageBytes);
        const mat = try imgbytes2matrix(imageBytes);
        const imageMat: ImageMat = .{ .mat = mat };
        self.imgMatrix = imageMat;
        std.debug.print("mat: {any}\n", .{mat});
    }
    // convert pixel to u32 and insert in led channel
    // rgba -> agrb
    // pixel is rgba, strip is grb big endian (ws2811 lib does not handle conversion to grb)
    pub fn setPixel(self: *Self, chan: usize, ledIdx: usize, colour: [4]u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        // Big endian + swap red and green
        const value: u32 = (@as(u32, colour[3]) << 24) | (@as(u32, colour[1]) << 16) | (@as(u32, colour[0]) << 8) | @as(u32, colour[2]);
        //const value: u32 = (@as(u32, 0) << 24) | (@as(u32, colour[1]) << 16) | (@as(u32, colour[0]) << 8) | @as(u32, colour[2]);
        //const value: u32 = std.mem.readPackedInt(u32, colour[0..4], 0, .big);
        //std.debug.print("colour: {x}, bigend: 0x{x:0>8}, 0x{x:0>8}\n", .{ colour, val1, val2 });
        if (@import("builtin").target.cpu.arch != std.Target.Cpu.Arch.x86_64) {
            self.ptr.*.channel[chan].leds[ledIdx] = value;
        } else {
            std.debug.print("colour: {x}, chan: {d}, ledIdx: {d}, bigend: 0x{x:0>8}\n", .{ colour, chan, ledIdx, value });
        }
    }

    ///////  Testing!
    pub fn renderFirstRow(self: *Self) void {
        const mat = self.imgMatrix;
        std.debug.print("row 0: {any}\n", .{mat.mat[0]});
        for (0..LEDSTRIP_COLS) |col| {
            const colour = mat.mat[0][col];
            self.setPixel(0, col, colour);
            self.setPixel(1, col, colour);
            std.debug.print("colour: {any}, ledIdx: {d}\n", .{ colour, col });
        }
        if (@import("builtin").target.cpu.arch != std.Target.Cpu.Arch.x86_64) {
            _ = ws2811.ws2811_render(self.ptr); // show row
        }
        //std.Thread.sleep(325000); // sleep 350us to balance frame rate of 5Hz
    }

    pub fn runFirstRow(self: *Self) !void {
        const start = try std.time.Instant.now();
        self.renderFirstRow();
        const end = try std.time.Instant.now();
        std.debug.print("ns spent on first line render: {}\n", .{end.since(start)});
        std.Thread.sleep(1000 * 1000); // 1ms
    }
    ///////  Testing!

    // render img to two strips, split in half, display in each channel
    // source image is 50x100 24bit, rotated and
    pub fn renderImg(self: *Self) void {
        // mat: [img.ROWS][img.COLS][4]u8
        const mat = self.imgMatrix;
        const half = LEDSTRIP_ROWS / 2; // split rows in two, one for each strip
        for (0..half) |i| {
            for (0..LEDSTRIP_COLS) |j| {
                self.setPixel(0, j, mat.mat[i][j]);
                self.setPixel(1, j, mat.mat[i + half][j]);
            }
            if (@import("builtin").target.cpu.arch != std.Target.Cpu.Arch.x86_64) {
                _ = ws2811.ws2811_render(self.ptr); // show row
            }
            //std.Thread.sleep(325000); // sleep 350us to balance frame rate of 5Hz
        }
    }

    pub fn lightAllLeds(self: *Self, col: u32) void {
        if (@import("builtin").target.cpu.arch != std.Target.Cpu.Arch.x86_64) {
            var i: usize = 0;
            var j: usize = 0;
            while (i < LEDSTRIP_COLS) : (i += 1) {
                self.ptr.*.channel[0].leds[i] = col;
            }
            while (j < LEDSTRIP_COLS) : (j += 1) {
                self.ptr.*.channel[1].leds[j] = col;
            }
            _ = ws2811.ws2811_render(self.ptr);
        }
    }

    // Startup, blink red, green and blue
    pub fn cycleColours(self: *Self) void {
        var timer = std.time.Timer.start() catch |err| {
            std.debug.print("err: {any}\n", .{err});
            return;
        };
        self.lightAllLeds(0xff0000);
        std.debug.print("ns spent on green cycle: {}\n", .{timer.lap()});
        std.Thread.sleep(500 * 1000 * 1000);
        timer.reset();
        self.lightAllLeds(0x00ff00);
        std.debug.print("ns spent on red cycle: {}\n", .{timer.lap()});
        std.Thread.sleep(500 * 1000 * 1000);
        timer.reset();
        self.lightAllLeds(0x0000ff);
        std.debug.print("ns spent on blue cycle: {}\n", .{timer.lap()});
        std.Thread.sleep(500 * 1000 * 1000);
        self.lightAllLeds(0x000000);
        std.Thread.sleep(1000 * 1000 * 1000);
    }

    pub fn toggleActive(self: *Self) void {
        self.activeMatrix = !self.activeMatrix;
    }

    pub fn runOnce(self: *Self) !void {
        const start = try std.time.Instant.now();
        self.renderImg();
        const end = try std.time.Instant.now();
        std.debug.print("ns spent on full render: {}\n", .{end.since(start)});
        std.Thread.sleep(1000 * 1000); // 1ms
    }

    pub fn cycleColumns(self: *Self, col: u32) void {
        if (@import("builtin").target.cpu.arch != std.Target.Cpu.Arch.x86_64) {
            for (0..LEDSTRIP_COLS) |x| {
                self.ptr.*.channel[0].leds[x] = col;
                self.ptr.*.channel[1].leds[x] = col;
                _ = ws2811.ws2811_render(self.ptr); // show row
                std.Thread.sleep(10 * 1000 * 1000);
                self.ptr.*.channel[0].leds[x] = 0;
                self.ptr.*.channel[1].leds[x] = 0;
                _ = ws2811.ws2811_render(self.ptr); // show row
            }
        }
    }

    pub fn u32ToU8Bytes(value: u32) [4]u8 {
        var buf: [4]u8 = undefined;
        std.mem.writeInt(u32, &buf, value, .big);
        return buf;
    }

    // event loop running in thread, set activeMatrix first
    pub fn runMatrix(self: *Self) !void {
        while (self.activeMatrix == true) {
            //ledController.rows(0xff0000);
            //ledController.cols(0x00ff00);
            const start = try std.time.Instant.now();
            self.renderImg();
            const end = try std.time.Instant.now();
            std.debug.print("ns spent on full render: {}\n", .{end.since(start)});
        }
    }

    // transform png data [][4]u8 to led matrix pixel vector (mat[row][col]pixel) [rows][cols][4]u8 prepared for led strip length
    // NB : image data sent over wire starts top left, we need to set pixels in same order
    pub fn imgbytes2matrix(bytes: []const u8) ![LEDSTRIP_ROWS][LEDSTRIP_COLS][4]u8 {
        var stream = std.io.fixedBufferStream(bytes);
        const reader = stream.reader();
        var mat: [LEDSTRIP_ROWS][LEDSTRIP_COLS][4]u8 = undefined;
        var pixel: [4]u8 = undefined; // in bigendian MSB format
        outer: for (0..LEDSTRIP_ROWS) |row| {
            for (0..LEDSTRIP_COLS) |col| {
                const bytes_read = try reader.read(pixel[0..]);
                if (bytes_read == 0) {
                    break :outer; // no more data
                }
                mat[row][col] = pixel;
            }
        }
        return mat;
    }
};

// Get WIFI IP address by fake UDP connection
pub fn getLocalAddress(alloc: Allocator) ![]const u8 {
    const addr = try std.net.Address.parseIp("1.1.1.1", 0);
    const sock = try posix.socket(posix.AF.INET, posix.SOCK.DGRAM, posix.IPPROTO.UDP);
    defer posix.close(sock);
    try posix.connect(sock, &addr.any, addr.getOsSockLen());

    var address: net.Address = undefined;
    var len: posix.socklen_t = @sizeOf(net.Address);
    try posix.getsockname(sock, &address.any, &len);
    const out = try std.fmt.allocPrint(alloc, "{any}", .{address});
    return out;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const arch = @import("builtin").target.cpu.arch;
    // Prints to stderr, shortcut based on `std.io.getStdErr()`
    std.debug.print("Testing zig for hologlobe Magic!.\n", .{});

    const addr = try getLocalAddress(allocator);
    std.debug.print("hologlobe IP addr: {s}\n", .{addr});

    const controlChip = gpiod.gpiod_chip_open_by_name("gpiochip0");

    var ledstrip: ws2811.ws2811_t = undefined;
    // ws281x
    // const ledChip = gpiod.gpiod_chip_open_by_name("gpiochip4");
    // var ledCtrl = ws281x.WS281x.init(ledChip, LEDSTRIP_PINA);
    // defer ledCtrl.deinit();
    // ledCtrl.showColor(0xff, 0xff, 0xa0);
    // ledCtrl.sendReset();

    // ws2811 init
    if (arch != std.Target.Cpu.Arch.x86_64) {
        ledstrip = ws2811.ws2811_t{
            .render_wait_time = 0,
            .device = null,
            .rpi_hw = null,
            .freq = 800000,
            .dmanum = 10,
            .channel = [2]ws2811.ws2811_channel_t{
                ws2811.ws2811_channel_t{
                    .gpionum = LEDSTRIP_PIN_A,
                    .invert = 0,
                    .count = LEDSTRIP_COLS,
                    .strip_type = ws2811.WS2811_STRIP_RGB,
                    .leds = null,
                    .brightness = 50,
                    .wshift = 0x00,
                    .rshift = 0x00,
                    .gshift = 0x00,
                    .bshift = 0x00,
                    .gamma = null,
                },
                ws2811.ws2811_channel_t{
                    .gpionum = LEDSTRIP_PIN_B,
                    .invert = 0,
                    .count = LEDSTRIP_COLS,
                    .strip_type = ws2811.WS2811_STRIP_RGB,
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

        // while (true) {
        //     //try control.pollButtonEvents();
        //     const start = try std.time.Instant.now();
        //     renderImg(&ledstrip, imgMatrix);
        //     const end = try std.time.Instant.now();
        //     std.debug.print("ns spent on full render: {}\n", .{end.since(start)});
        //     std.Thread.sleep(1000 * 1000); // 1ms
        // }
    }
    // SPI AND DISPLAY INIT
    if (arch != std.Target.Cpu.Arch.x86_64) {
        const fd = try fs.openFileAbsolute("/dev/spidev0.0", fs.File.OpenFlags{
            .mode = .read_write,
        });
        defer fd.close();
        const spiDev = ssd1305.SPIDevice{
            .fd = fd,
            .speedHz = 4000000, // 125000000 Hz max, but +7Mhz will probably give blank
            .csChange = 0,
            .mode = 0x04, // MODE_3
            .bpw = 8,
            .delayUsecs = 0,
        };

        // spi, dc, rst, cs
        spiBus = ssd1305.SpiBus.init(spiDev, 25, 24, 8);
        std.debug.print("ssd1305 spi bus initiated\n", .{});
        const config = ssd1305.Config{
            .Width = 128,
            .Height = 32,
            .Rotation = 2, // 180 degrees
            .VccState = ssd1305.EXTERNALVCC,
        };
        display = try ssd1305.Display.init(allocator, config, &spiBus);

        // Initialize display registry
        try display.initReg();
        std.Thread.sleep(200 * 1000 * 1000); // 200ms
        // Turn on the OLED display
        display.Command(ssd1305.DISPLAYON);
        std.debug.print("ssd1305 display initiated!\n", .{});

        // print logo
        try display.SetBuffer(logoBuffer, buflen);
        display.Display();
        std.Thread.sleep(1 * 1000 * 1000 * 1000); // 1s

        // show local ip on display
        display.ClearDisplay();
        display.writeLine(addr, 0);
        display.Display();
        std.Thread.sleep(2 * 1000 * 1000 * 1000); // 1s

        // start
        display.ClearDisplay();
        display.writeLine(" HOLOGLOBE ", 0);
        display.Display();

        // we need to hold GPIO and Display allocated until exit
        defer spiBus.deinit();
        defer display.deinit();
    }

    var controller = Control.init(controlChip);
    defer controller.deinit();

    var ledController = try LedControl.init(allocator, &ledstrip);
    try ledController.setInitialImg();
    defer ledController.deinit();

    var server = try Server.init(allocator, 8765, controller, &ledController);
    defer server.deinit();

    try server.serve();
}

const SSD1305_LCDHEIGHT = 32;
const SSD1305_LCDWIDTH = 128;
const buflen = SSD1305_LCDHEIGHT * SSD1305_LCDWIDTH / 8;
var logoBuffer: [buflen]u8 = [buflen]u8{
    // 'paels-128x32', 128x32px (16 x 32 bytes x 8 bits)
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x40, 0xa0, 0xa0, 0xd0, 0x10, 0x70, 0x40, 0x30, 0xa0, 0x20, 0xc0, 0x90, 0xb0, 0x60,
    0x20, 0x60, 0x60, 0xa0, 0xe0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80, 0xe0, 0xb0, 0x20, 0x10, 0x10,
    0x20, 0x40, 0x50, 0x70, 0xd0, 0xc0, 0x90, 0x90, 0x20, 0x20, 0x10, 0xd0, 0xd0, 0x00, 0x90, 0xf0,
    0xe0, 0x20, 0xe0, 0x00, 0x00, 0x00, 0x00, 0x20, 0x60, 0x30, 0x00, 0x60, 0x30, 0xa0, 0xc0, 0xf0,
    0xb0, 0x60, 0x20, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0x60, 0x20, 0xb0, 0x10, 0xe0,
    0x60, 0xd0, 0x80, 0xe0, 0x90, 0x60, 0x60, 0xe0, 0x30, 0xe0, 0xe0, 0x60, 0xc0, 0xc0, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x08, 0xcd, 0xb5, 0x98, 0x46, 0x69, 0x89, 0x36, 0x7b, 0x82, 0x40, 0xc0, 0x80, 0x23,
    0xb5, 0xdc, 0x63, 0x29, 0xd8, 0xf7, 0x24, 0x00, 0x00, 0x00, 0xe8, 0x6b, 0x8b, 0x26, 0x12, 0x19,
    0x39, 0x23, 0xde, 0x63, 0x21, 0xc1, 0x01, 0xa1, 0xa1, 0x21, 0x01, 0x20, 0xa1, 0xe1, 0x81, 0xc0,
    0xc1, 0x02, 0x01, 0x00, 0x00, 0x00, 0x80, 0x64, 0x45, 0x89, 0xeb, 0x24, 0xb5, 0x4b, 0xfc, 0xf6,
    0x1f, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x05, 0x31, 0x1c, 0xe7, 0xa1, 0x5a, 0x5b,
    0xcf, 0xdc, 0x30, 0x60, 0xe0, 0xc0, 0xc1, 0xc5, 0xc6, 0x86, 0x05, 0x07, 0x07, 0x03, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x10, 0xf6, 0xf6, 0x89, 0x6e, 0xa9, 0xd1, 0x37, 0xed, 0x73, 0x02, 0x03, 0x03, 0x03,
    0x02, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0xc0, 0x28, 0x2e, 0x23, 0x48, 0x59, 0x33, 0xf3, 0x07,
    0x06, 0x03, 0x4f, 0xaa, 0x89, 0x5c, 0xf2, 0x82, 0x42, 0x03, 0x43, 0xc0, 0x83, 0x02, 0x62, 0x83,
    0xc0, 0x40, 0xc0, 0x80, 0x00, 0x60, 0x4d, 0xb1, 0x3c, 0x89, 0xb0, 0xcf, 0x59, 0x7f, 0xdf, 0x84,
    0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x00, 0x80, 0x80, 0x80, 0x80, 0x00, 0xf0, 0x10, 0x31, 0x81,
    0xf0, 0xf2, 0x81, 0x83, 0x82, 0x85, 0x05, 0x6d, 0x91, 0x9f, 0xe7, 0xb7, 0xff, 0xde, 0x78, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x02, 0x03, 0x07, 0x03, 0x03, 0x03, 0x07, 0x07, 0x01, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03, 0x03, 0x03, 0x03, 0x02, 0x03, 0x07, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x03, 0x03, 0x02, 0x06, 0x05, 0x05, 0x06, 0x04, 0x04, 0x07, 0x06, 0x04, 0x06,
    0x04, 0x03, 0x03, 0x00, 0x00, 0x00, 0x03, 0x03, 0x06, 0x06, 0x01, 0x06, 0x02, 0x03, 0x06, 0x02,
    0x01, 0x03, 0x03, 0x03, 0x06, 0x03, 0x03, 0x07, 0x07, 0x07, 0x00, 0x00, 0x03, 0x02, 0x07, 0x03,
    0x04, 0x03, 0x03, 0x07, 0x07, 0x06, 0x03, 0x03, 0x03, 0x03, 0x06, 0x03, 0x01, 0x01, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
};
