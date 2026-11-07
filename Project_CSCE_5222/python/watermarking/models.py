"""Shared image types and embedding and extraction results."""

from dataclasses import dataclass

import numpy as np
from numpy.typing import NDArray


ImageArray = NDArray[np.uint8]


class WatermarkError(ValueError):
    """Report a bad input or damaged watermark."""


@dataclass(frozen=True)
class EmbeddingResult:
    """Keep the marked image and the settings used to make it."""
    image: ImageArray
    prepared_watermark: ImageArray
    strength: int
    psnr: float


@dataclass(frozen=True)
class ExtractionResult:
    """Keep the recovered watermark and its check result."""
    watermark: ImageArray
    strength: int
    verified: bool = True
