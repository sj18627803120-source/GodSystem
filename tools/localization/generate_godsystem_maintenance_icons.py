from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "Contents" / "mods" / "GodSystem" / "42" / "media" / "textures"
SCALE = 4
SIZE = 32


def canvas() -> tuple[Image.Image, ImageDraw.ImageDraw]:
    image = Image.new("RGBA", (SIZE * SCALE, SIZE * SCALE), (0, 0, 0, 0))
    return image, ImageDraw.Draw(image)


def points(values: list[tuple[int, int]]) -> list[tuple[int, int]]:
    return [(x * SCALE, y * SCALE) for x, y in values]


def rect(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], fill, outline=None, width=1) -> None:
    draw.rectangle(tuple(value * SCALE for value in box), fill=fill, outline=outline, width=width * SCALE)


def line(draw: ImageDraw.ImageDraw, values: list[tuple[int, int]], fill, width=1) -> None:
    draw.line(points(values), fill=fill, width=width * SCALE, joint="curve")


def finish(image: Image.Image, name: str) -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    image.resize((SIZE, SIZE), Image.Resampling.LANCZOS).save(OUTPUT / name, "PNG")


def repair_kit() -> None:
    image, draw = canvas()
    rect(draw, (5, 7, 27, 27), (43, 48, 51, 255), (18, 20, 22, 255), 2)
    rect(draw, (8, 10, 24, 24), (66, 73, 76, 255), (181, 139, 52, 255), 1)
    rect(draw, (11, 5, 21, 9), (53, 58, 61, 255), (18, 20, 22, 255), 1)
    rect(draw, (14, 6, 18, 8), (181, 139, 52, 255))
    draw.ellipse((9 * SCALE, 19 * SCALE, 14 * SCALE, 24 * SCALE), fill=(190, 201, 204, 255), outline=(70, 77, 80, 255), width=SCALE)
    line(draw, [(12, 21), (21, 12)], (210, 220, 222, 255), 3)
    draw.polygon(points([(19, 9), (23, 9), (21, 12), (24, 15), (21, 17), (17, 13)]), fill=(210, 220, 222, 255), outline=(70, 77, 80, 255))
    rect(draw, (18, 19, 24, 21), (78, 178, 109, 255))
    rect(draw, (20, 17, 22, 23), (78, 178, 109, 255))
    finish(image, "Item_SystemRepairKit.png")


def durability_core() -> None:
    image, draw = canvas()
    outer = [(16, 3), (25, 8), (28, 17), (23, 26), (14, 29), (5, 23), (4, 13), (9, 6)]
    inner = [(16, 7), (22, 10), (24, 17), (20, 23), (14, 25), (8, 21), (8, 14), (11, 9)]
    draw.polygon(points(outer), fill=(43, 48, 52, 255), outline=(18, 20, 22, 255))
    line(draw, outer + [outer[0]], (190, 145, 49, 255), 2)
    draw.polygon(points(inner), fill=(38, 117, 135, 255), outline=(119, 213, 220, 255))
    draw.polygon(points([(16, 10), (21, 14), (20, 20), (15, 23), (10, 19), (11, 13)]), fill=(101, 207, 216, 255))
    draw.polygon(points([(16, 12), (19, 15), (18, 19), (15, 21), (12, 18), (13, 14)]), fill=(216, 243, 238, 255))
    line(draw, [(6, 13), (10, 14)], (206, 166, 72, 255), 1)
    line(draw, [(22, 10), (25, 8)], (206, 166, 72, 255), 1)
    line(draw, [(22, 23), (25, 25)], (206, 166, 72, 255), 1)
    finish(image, "Item_DurabilityCore.png")


def system_space_terminal() -> None:
    image, draw = canvas()
    outer = [(16, 3), (26, 8), (29, 18), (23, 27), (10, 27), (3, 18), (6, 8)]
    inner = [(16, 7), (23, 10), (25, 18), (20, 23), (12, 23), (7, 18), (9, 10)]
    draw.polygon(points(outer), fill=(25, 35, 51, 255), outline=(7, 11, 18, 255))
    line(draw, outer + [outer[0]], (55, 154, 224, 255), 2)
    draw.polygon(points(inner), fill=(23, 94, 143, 255), outline=(105, 221, 239, 255))
    rect(draw, (11, 12, 21, 20), (8, 28, 48, 255), (162, 237, 243, 255), 1)
    rect(draw, (13, 14, 19, 18), (54, 177, 209, 255))
    rect(draw, (15, 15, 17, 17), (224, 252, 249, 255))
    line(draw, [(8, 8), (11, 11)], (218, 171, 54, 255), 1)
    line(draw, [(24, 8), (21, 11)], (218, 171, 54, 255), 1)
    rect(draw, (14, 25, 18, 27), (218, 171, 54, 255))
    finish(image, "Item_SystemSpaceTerminal.png")


def vehicle_repair_module() -> None:
    image, draw = canvas()
    rect(draw, (4, 6, 28, 26), (45, 49, 54, 255), (15, 18, 21, 255), 2)
    rect(draw, (7, 9, 25, 23), (92, 52, 33, 255), (229, 133, 57, 255), 1)
    for x in (7, 11, 15, 19, 23):
        rect(draw, (x, 4, x + 2, 7), (203, 157, 66, 255))
        rect(draw, (x, 25, x + 2, 28), (203, 157, 66, 255))
    draw.polygon(points([(9, 18), (11, 13), (21, 13), (24, 18), (24, 21), (21, 21), (20, 19), (12, 19), (11, 21), (8, 21)]), fill=(202, 216, 218, 255), outline=(61, 70, 73, 255))
    rect(draw, (12, 15, 20, 17), (62, 145, 182, 255))
    draw.ellipse((9 * SCALE, 18 * SCALE, 13 * SCALE, 22 * SCALE), fill=(26, 31, 35, 255), outline=(218, 171, 67, 255), width=SCALE)
    draw.ellipse((20 * SCALE, 18 * SCALE, 24 * SCALE, 22 * SCALE), fill=(26, 31, 35, 255), outline=(218, 171, 67, 255), width=SCALE)
    line(draw, [(18, 10), (22, 6)], (239, 225, 188, 255), 2)
    draw.polygon(points([(20, 5), (25, 4), (24, 9), (22, 10), (20, 8)]), fill=(239, 225, 188, 255), outline=(74, 78, 79, 255))
    finish(image, "Item_SystemVehicleRepairModule.png")


if __name__ == "__main__":
    repair_kit()
    durability_core()
    system_space_terminal()
    vehicle_repair_module()
    print(f"generated maintenance icons in {OUTPUT}")
