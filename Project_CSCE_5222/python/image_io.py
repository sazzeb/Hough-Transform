import os
from pathlib import Path
import tempfile

import numpy as np
from PIL import Image

from watermark_core import (
    ImageArray,
    WatermarkEngine,
    WatermarkError,
)


class ImageStore:
    """Read supported inputs and save verified, lossless PNG outputs."""

    MAX_INPUT_PIXELS = 24_000_000

    @staticmethod
    def read(
        path: str | Path,
        watermarked: bool = False,
    ) -> ImageArray:
        path = Path(path)

        with Image.open(path) as source:
            if source.width * source.height > ImageStore.MAX_INPUT_PIXELS:
                raise WatermarkError(
                    "The image is too large to process safely. "
                    "Choose an image of 24 megapixels or less."
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
                        "Load the unmodified grayscale/RGB PNG "
                        "saved by this app."
                    )

                result = np.asarray(source).copy()

            elif (
                source.mode in {"1", "L"}
                and "transparency" not in source.info
            ):
                result = np.asarray(
                    source.convert("L")
                ).copy()

            elif (
                source.mode in {"RGB", "P"}
                and "transparency" not in source.info
            ):
                result = np.asarray(
                    source.convert("RGB")
                ).copy()

            elif source.mode in {
                "1", "L", "P", "LA", "RGB", "RGBA"
            }:
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

            else:
                raise WatermarkError(
                    "Unsupported image mode; "
                    "convert the input to 8-bit RGB."
                )

        WatermarkEngine.validate_image(result)
        return result

    @staticmethod
    def save_png(
        path: str | Path,
        image: ImageArray,
    ) -> Path:
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
