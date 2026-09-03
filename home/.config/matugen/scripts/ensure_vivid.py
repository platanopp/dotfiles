import colorsys
import sys

vivid_targets = {
    "color1", "color2", "color3", "color4", "color5", "color6",
    "color9", "color10", "color11", "color12", "color13", "color14",
}

bright_targets = {"foreground", "cursor"}


def ensure_vivid(hex_code):
    h = hex_code.lstrip("#")
    r, g, b = int(h[0:2], 16) / 255, int(h[2:4], 16) / 255, int(h[4:6], 16) / 255
    hue, lightness, saturation = colorsys.rgb_to_hls(r, g, b)
    if lightness < 0.58:
        lightness = 0.58
    if lightness > 0.78:
        lightness = 0.78
    if saturation < 0.5:
        saturation = 0.5
    r, g, b = colorsys.hls_to_rgb(hue, lightness, saturation)
    return "#{:02x}{:02x}{:02x}".format(round(r * 255), round(g * 255), round(b * 255))


def ensure_bright(hex_code):
    h = hex_code.lstrip("#")
    r, g, b = int(h[0:2], 16) / 255, int(h[2:4], 16) / 255, int(h[4:6], 16) / 255
    hue, lightness, saturation = colorsys.rgb_to_hls(r, g, b)
    if lightness < 0.8:
        lightness = 0.8
    r, g, b = colorsys.hls_to_rgb(hue, lightness, saturation)
    return "#{:02x}{:02x}{:02x}".format(round(r * 255), round(g * 255), round(b * 255))


def main():
    path = sys.argv[1]
    with open(path) as f:
        lines = f.readlines()

    output = []
    for line in lines:
        parts = line.split()
        if len(parts) == 2 and parts[0] in vivid_targets:
            parts[1] = ensure_vivid(parts[1])
            output.append(parts[0] + " " + parts[1] + "\n")
        elif len(parts) == 2 and parts[0] in bright_targets:
            parts[1] = ensure_bright(parts[1])
            output.append(parts[0] + " " + parts[1] + "\n")
        else:
            output.append(line)

    with open(path, "w") as f:
        f.writelines(output)


if __name__ == "__main__":
    main()
