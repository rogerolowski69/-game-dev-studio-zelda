"""The shared colour palette. Every sprite and tile draws from these names."""

C = {
    "outline": (20, 20, 32),
    "ink": (43, 43, 69),
    "white": (244, 244, 244),
    # vegetation
    "grass_dark": (46, 107, 48),
    "grass": (63, 154, 58),
    "grass_light": (108, 194, 74),
    "grass_hi": (168, 224, 95),
    "leaf_dark": (28, 74, 40),
    "leaf": (44, 120, 52),
    "leaf_light": (86, 170, 70),
    "trunk_dark": (74, 47, 31),
    "trunk": (122, 74, 42),
    # earth & rock
    "cliff_dark": (104, 62, 36),
    "cliff": (160, 104, 58),
    "cliff_light": (210, 152, 96),
    "sand_dark": (201, 160, 98),
    "sand": (232, 201, 138),
    "sand_light": (245, 227, 179),
    "stone_dark": (70, 70, 88),
    "stone": (118, 118, 138),
    "stone_light": (172, 172, 190),
    "stone_hi": (214, 214, 226),
    "cave_dark": (22, 18, 26),
    "cave": (44, 36, 46),
    "cave_light": (74, 62, 72),
    # water
    "water_deep": (31, 63, 143),
    "water": (47, 111, 208),
    "water_light": (95, 168, 240),
    "foam": (210, 240, 255),
    # accents
    "red": (206, 58, 58),
    "red_dark": (130, 30, 44),
    "red_light": (246, 140, 110),
    "orange": (240, 138, 60),
    "gold": (255, 214, 72),
    "gold_dark": (196, 146, 38),
    "gold_light": (255, 244, 170),
    "skin": (242, 180, 138),
    "skin_dark": (200, 128, 90),
    "teal": (42, 138, 138),
    "teal_dark": (29, 95, 95),
    "teal_light": (74, 200, 200),
    "purple": (122, 60, 154),
    "purple_dark": (74, 34, 106),
    "purple_light": (176, 112, 214),
    "cyan": (96, 222, 232),
    "cyan_dark": (36, 140, 172),
    "blue": (80, 120, 240),
    "blue_dark": (40, 60, 160),
    "heart_empty": (96, 36, 52),
    "flower_pink": (255, 150, 190),
}


def rgba(name: str, alpha: int = 255) -> tuple:
    return C[name] + (alpha,)
