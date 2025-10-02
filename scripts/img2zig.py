#!/usr/bin/env python3

import sys
import os
from PIL import Image

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: %s [image name]" % (sys.argv[0]))
        sys.exit(-1)

    im = Image.open(sys.argv[1])
    #rotated = im.rotate(-90, expand=True) # expand=True ensures the whole image is visible
    #width, height = rotated.size
    # width = number of cols in orig matrix
    # height = number of rows in orig matrix
    width, height = im.size
    f = open("img.zig", "w+")
    f.write("pub const ROWS = %d;\n" % (height)) # height BEFORE rotate
    f.write("pub const COLS = %d;\n" % (width))  # width BEFORE rotate
    f.write("pub const DATA = [_]u8{")

    #out = Image.new('RGB', (width, height), color='black') # output rotated img
    #pixels = im.load()
    #read out pixels from left to right / rotated
    # for y in range(0, height):
    #     for x in range(0, width):
    #         #if x == 2:
    #         #    break
    #         r, g, b = pixels[x, y]
    #         f.write("%s, " % hex(0))
    #         f.write("%s, " % hex(r))
    #         f.write("%s, " % hex(g))
    #         f.write("%s, " % hex(b))

    #         #out.putpixel((y, width - x - 1), (r,g,b))
    #         out.putpixel((height - y - 1, x), (r,g,b))
    #pixels = rotated.load()
    pixels = im.load()
    for y in range(0, height):
        for x in range(0, width):
            #if x == 2:
            #    break
            r, g, b, a = pixels[x, y]
            f.write("%s, " % hex(r))
            f.write("%s, " % hex(g))
            f.write("%s, " % hex(b))
            f.write("%s, " % hex(a))
    f.write("};\n")
    f.close()
    #rotated.save("output.png")
