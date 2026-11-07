"""Blockwise Haar wavelet transform used by the watermark engine."""

import numpy as np
from numpy.typing import NDArray


class HaarTransform:
    """One-level orthonormal Haar transform of row-major 2-by-2 blocks."""

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
        return np.asarray(blocks, dtype=np.float64) @ HaarTransform.MATRIX.T

    @staticmethod
    def inverse(coefficients: NDArray) -> NDArray[np.float64]:
        return np.asarray(coefficients, dtype=np.float64) @ HaarTransform.MATRIX
