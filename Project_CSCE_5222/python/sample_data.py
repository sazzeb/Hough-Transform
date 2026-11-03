"""Bundled Unsplash examples for the watermark workflow."""

import json
from pathlib import Path
import random

import numpy as np
from PIL import Image, ImageDraw, ImageOps

from image_io import ImageStore
from watermark_core import ImageArray


class ExampleGallery:
    """Shuffle every bundled photo once before starting another round."""

    def __init__(self, catalog_path: Path | None = None, rng=None):
        self.catalog_path = catalog_path or (
            Path(__file__).resolve().parent.parent
            / "matlab" / "source" / "images" / "catalog.json"
        )
        self.entries = json.loads(self.catalog_path.read_text(encoding="utf-8"))
        if len(self.entries) < 10:
            raise ValueError("The example gallery needs at least 10 photos.")
        if len({entry["id"] for entry in self.entries}) != len(self.entries):
            raise ValueError("The example gallery contains duplicate photos.")
        self.random = rng or random.Random()
        self.remaining = []
        self.last_index = None

    def next_example(self):
        if not self.remaining:
            self.remaining = list(range(len(self.entries)))
            self.random.shuffle(self.remaining)
            if self.remaining[-1] == self.last_index:
                self.remaining[0], self.remaining[-1] = (
                    self.remaining[-1], self.remaining[0]
                )

        index = self.remaining.pop()
        self.last_index = index
        cover = self.entries[index]
        watermark = self.entries[(index + 5) % len(self.entries)]
        directory = self.catalog_path.parent
        return {
            "title": cover["title"],
            "cover_source": cover["source_url"],
            "watermark_source": watermark["source_url"],
            "cover_path": directory / f"{cover['id']}.jpg",
            "watermark_path": directory / f"{watermark['id']}.jpg",
        }


def load_example_images(example) -> tuple[ImageArray, ImageArray]:
    """Load a photograph and make a compact square watermark from another."""
    cover = ImageStore.read(example["cover_path"])
    with Image.open(example["watermark_path"]) as source:
        watermark = ImageOps.fit(
            source.convert("L"), (96, 96), method=Image.Resampling.LANCZOS
        )
        return cover, np.asarray(watermark).copy()


def load_sample_images() -> tuple[ImageArray, ImageArray]:
    """Return the supplied photograph and a separate, generated logo image."""
    photograph = (
        Path(__file__).resolve().parent.parent
        / "matlab" / "source" / "images" / "sample_cover.jpg"
    )
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
