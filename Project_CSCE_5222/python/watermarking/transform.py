"""Blockwise Haar wavelet transform used by the watermark engine."""

import numpy as np
from numpy.typing import NDArray


class HaarTransform:
    """Convert 2-by-2 pixel blocks to and from Haar values."""

    MATRIX = np.array(
        [
            [1, 1, 1, 1],
            [1, -1, 1, -1],
            [1, 1, -1, -1],
            [1, -1, -1, 1],
        ],
        dtype=np.float64,
    ) / 2.0

    @staticmethod
    def forward(blocks: NDArray) -> NDArray[np.float64]:
        """Turn pixel blocks into Haar wavelet values."""
        return np.asarray(blocks, dtype=np.float64) @ HaarTransform.MATRIX.T

    @staticmethod
    def inverse(coefficients: NDArray) -> NDArray[np.float64]:
        """Turn Haar wavelet values back into pixel blocks."""
        return np.asarray(coefficients, dtype=np.float64) @ HaarTransform.MATRIX
