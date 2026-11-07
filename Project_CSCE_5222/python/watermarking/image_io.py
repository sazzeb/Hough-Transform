"""Open source images and save verified PNG results."""

import os
from pathlib import Path
import tempfile
from math import sqrt

import numpy as np
from PIL import Image

from .engine import (
    ImageArray,
    WatermarkEngine,
    WatermarkError,
)


class ImageStore:
    """Load images safely and save checked PNG results."""

    MAX_WORKING_PIXELS = 12_000_000
    MAX_SOURCE_PIXELS = 100_000_000
    MAX_WATERMARKED_PIXELS = 24_000_000

    @staticmethod
    def read(
        path: str | Path,
        watermarked: bool = False,
    ) -> ImageArray:
        """Open an image and convert it to safe 8-bit pixels."""
        path = Path(path)

        with Image.open(path) as source:
            source_pixels = source.width * source.height

            if watermarked and source_pixels > ImageStore.MAX_WATERMARKED_PIXELS:
                raise WatermarkError(
                    f"The selected file is {source.width} × {source.height} "
                    f"pixels ({source_pixels / 1_000_000:.1f} MP), above "
                    "the 24 MP recovery limit. If this is your original "
                    "photo, load it as a cover, embed the watermark, and "
                    "select the PNG saved with Save watermarked PNG. "
                    "Resizing this file cannot recover a watermark."
                )

            if source_pixels > ImageStore.MAX_SOURCE_PIXELS:
                raise WatermarkError(
                    "The source image exceeds the 100 megapixel safety limit."
                )

            if source.format not in {"PNG", "JPEG", "BMP"}:
                raise WatermarkError(
                    "Supported inputs are PNG, JPEG and BMP."
                )

            if getattr(source, "n_frames", 1) != 1:
                raise WatermarkError(
                    "Use a single-frame image."
                )

            if source.format == "PNG":
                with path.open("rb") as stream:
                    signature = stream.read(26)

                if len(signature) != 26 or signature[24] > 8:
                    raise WatermarkError(
                        "Convert 16-bit PNG images to 8-bit before loading."
                    )

            if watermarked:
                if (
                    source.format != "PNG"
                    or source.mode not in {"L", "RGB"}
                    or "transparency" in source.info
                ):
                    raise WatermarkError(
                        "This file is not an opaque 8-bit grayscale or "
                        "RGB PNG. Choose the exact file saved with Save "
                        "watermarked PNG. An original photo or recovered "
                        "watermark cannot be used for recovery."
                    )

                result = np.asarray(source).copy()

            else:
                if source_pixels > ImageStore.MAX_WORKING_PIXELS:
                    scale = sqrt(
                        ImageStore.MAX_WORKING_PIXELS / source_pixels
                    )
                    working_size = (
                        max(1, int(source.width * scale)),
                        max(1, int(source.height * scale)),
                    )
                    if (
                        source.format == "JPEG"
                        and source_pixels
                        > 4 * ImageStore.MAX_WORKING_PIXELS
                    ):
                        source.draft("RGB", working_size)
                    elif source.format == "JPEG":
                        source.load()
                    source.thumbnail(
                        working_size, Image.Resampling.LANCZOS
                    )

                result = ImageStore._as_array(source)

        WatermarkEngine.validate_image(result)
        return result

    @staticmethod
    def _as_array(source: Image.Image) -> ImageArray:
        """Convert grayscale, color, or transparent input to an array."""
        if (
            source.mode in {"1", "L"}
            and "transparency" not in source.info
        ):
            return np.asarray(source.convert("L")).copy()

        if (
            source.mode in {"RGB", "P"}
            and "transparency" not in source.info
        ):
            return np.asarray(source.convert("RGB")).copy()

        if source.mode in {"1", "L", "P", "LA", "RGB", "RGBA"}:
            rgba = np.asarray(source.convert("RGBA"))
            alpha = rgba[:, :, 3].astype(np.uint16)
            background = 255 - alpha
            result = np.empty(
                (source.height, source.width, 3),
                dtype=np.uint8,
            )

            for channel in range(3):
                foreground = rgba[:, :, channel].astype(np.uint16)
                result[:, :, channel] = (
                    (foreground * alpha + 127) // 255
                    + background
                ).astype(np.uint8)

            return result

        raise WatermarkError(
            "Unsupported image mode; "
            "convert the input to 8-bit RGB."
        )

    @staticmethod
    def save_png(
        path: str | Path,
        image: ImageArray,
    ) -> Path:
        """Save a PNG and reopen it to check every pixel."""
        WatermarkEngine.validate_image(image)

        target = Path(path).expanduser().resolve()

        if target.suffix.lower() != ".png":
            raise WatermarkError(
                "Output filenames must end in .png."
            )

        if not target.parent.is_dir():
            raise WatermarkError(
                "The output directory does not exist."
            )

        descriptor, temporary_name = tempfile.mkstemp(
            prefix=".watermark-",
            suffix=".png",
            dir=target.parent,
        )

        os.close(descriptor)
        temporary = Path(temporary_name)

        try:
            Image.fromarray(image).save(
                temporary,
                format="PNG",
            )

            reloaded = ImageStore.read(
                temporary,
                watermarked=True,
            )

            if not np.array_equal(image, reloaded):
                raise WatermarkError(
                    "PNG verification failed; "
                    "the output was not replaced."
                )

            os.replace(temporary, target)

        finally:
            temporary.unlink(missing_ok=True)

        return target
