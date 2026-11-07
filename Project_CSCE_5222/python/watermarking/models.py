"""Shared image types and embedding and extraction results."""

from dataclasses import dataclass

import numpy as np
from numpy.typing import NDArray


ImageArray = NDArray[np.uint8]


class WatermarkError(ValueError):
    """An input or embedded watermark is not valid."""


@dataclass(frozen=True)
class EmbeddingResult:
    image: ImageArray
    prepared_watermark: ImageArray
    strength: int
    psnr: float


@dataclass(frozen=True)
class ExtractionResult:
    watermark: ImageArray
    strength: int
    verified: bool = True
