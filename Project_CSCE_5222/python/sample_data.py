"""Small, repeatable images for trying the watermark workflow."""

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from image_io import ImageStore
from watermark_core import ImageArray


def load_sample_images() -> tuple[ImageArray, ImageArray]:
    """Return the supplied photograph and a separate, generated logo image."""
    photograph = Path(__file__).with_name("sample_cover.jpg")
    cover = ImageStore.read(photograph)

    logo = Image.new("L", (96, 96), 245)
    drawing = ImageDraw.Draw(logo)
    drawing.rounded_rectangle(
        (4, 4, 91, 91), radius=16, fill=232, outline=25, width=4
    )
    drawing.line(
        [(15, 24), (27, 72), (48, 39), (69, 72), (81, 24)],
        fill=20,
        width=10,
        joint="curve",
    )

    return cover, np.asarray(logo).copy()
