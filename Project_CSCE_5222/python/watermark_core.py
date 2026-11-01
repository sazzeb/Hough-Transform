from dataclasses import dataclass
import math
import struct
import zlib

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
        return (
            np.asarray(blocks, dtype=np.float64)
            @ HaarTransform.MATRIX.T
        )

    @staticmethod
    def inverse(coefficients: NDArray) -> NDArray[np.float64]:
        return (
            np.asarray(coefficients, dtype=np.float64)
            @ HaarTransform.MATRIX
        )


class WatermarkEngine:
    MAGIC = b"WVM1"
    REPEATS = 3
    HEADER_STRENGTH = 16
    HEADER_BYTES = 24
    HEADER_SLOTS = HEADER_BYTES * 8 * REPEATS
    HEADER = struct.Struct(">4sBBBBHHII")

    @staticmethod
    def validate_image(image: ImageArray) -> None:
        if not isinstance(image, np.ndarray) or image.dtype != np.uint8:
            raise WatermarkError("Use a uint8 NumPy image.")

        if image.ndim != 2 and not (
            image.ndim == 3 and image.shape[2] == 3
        ):
            raise WatermarkError("Use a grayscale or RGB image.")

        if image.size == 0:
            raise WatermarkError("The image is empty.")


    @staticmethod
    def _integer(
        value: int,
        low: int,
        high: int,
        name: str,
    ) -> int:
        if isinstance(value, (bool, np.bool_)) or not isinstance(
            value, (int, np.integer)
        ):
            raise WatermarkError(
                f"{name} must be a whole number."
            )

        if not low <= value <= high:
            raise WatermarkError(
                f"{name} must be from {low} to {high}."
            )

        return int(value)

    @staticmethod
    def prepare_watermark(
        image: ImageArray,
        size: tuple[int, int] = (32, 32),
    ) -> ImageArray:
        WatermarkEngine.validate_image(image)

        if not isinstance(size, (tuple, list)) or len(size) != 2:
            raise WatermarkError(
                "Watermark size must be (height, width)."
            )

        height = WatermarkEngine._integer(
            size[0], 8, 64, "Watermark height"
        )

        width = WatermarkEngine._integer(
            size[1], 8, 64, "Watermark width"
        )

        values = image.astype(np.float64)

        if image.ndim == 3:
            # Integer weights make the grayscale convention reproducible.
            values = (
                299 * values[:, :, 0]
                + 587 * values[:, :, 1]
                + 114 * values[:, :, 2]
            ) / 1000

        source_rows = np.arange(height) * (values.shape[0] - 1) / (height - 1)
        source_columns = np.arange(width) * (values.shape[1] - 1) / (width - 1)
        row0 = np.floor(source_rows).astype(np.int64)
        column0 = np.floor(source_columns).astype(np.int64)
        row1 = np.minimum(row0 + 1, values.shape[0] - 1)
        column1 = np.minimum(column0 + 1, values.shape[1] - 1)
        row_weight = source_rows - row0
        column_weight = source_columns - column0

        top = (
            values[row0[:, None], column0[None, :]]
            * (1 - column_weight)[None, :]
            + values[row0[:, None], column1[None, :]]
            * column_weight[None, :]
        )
        bottom = (
            values[row1[:, None], column0[None, :]]
            * (1 - column_weight)[None, :]
            + values[row1[:, None], column1[None, :]]
            * column_weight[None, :]
        )

        return np.floor(
            top * (1 - row_weight)[:, None]
            + bottom * row_weight[:, None]
            + 0.5
        ).astype(np.uint8)

    @staticmethod
    def capacity_bytes(image: ImageArray) -> int:
        WatermarkEngine.validate_image(image)

        slots = (
            2
            * (image.shape[0] // 2)
            * (image.shape[1] // 2)
        )

        return max(
            0,
            slots // (8 * WatermarkEngine.REPEATS)
            - WatermarkEngine.HEADER_BYTES,
        )

    @staticmethod
    def _blocks(
        image: ImageArray,
        count: int | None = None,
        channel: int = 0,
    ) -> NDArray[np.float64]:
        plane = image if image.ndim == 2 else image[:, :, channel]

        width = 2 * (plane.shape[1] // 2)
        blocks_per_row = width // 2
        available = (plane.shape[0] // 2) * blocks_per_row

        if count is None:
            count = available

        if not 0 <= count <= available:
            raise WatermarkError("Requested image blocks are unavailable.")

        # Only visit rows holding the header and payload. A large cover can
        # otherwise require several full-size floating-point copies.
        block_rows = (
            0
            if count == 0
            else (count + blocks_per_row - 1) // blocks_per_row
        )
        height = 2 * block_rows

        blocks = np.column_stack(
            [
                plane[row:height:2, column:width:2].ravel()
                for row, column in (
                    (0, 0),
                    (0, 1),
                    (1, 0),
                    (1, 1),
                )
            ]
        ).astype(np.float64)

        return blocks[:count]

    @staticmethod
    def _write_blocks(
        image: ImageArray,
        blocks: NDArray,
        channel: int = 0,
    ) -> ImageArray:
        output = image.copy()

        plane = output if output.ndim == 2 else output[:, :, channel]

        height = 2 * (plane.shape[0] // 2)
        width = 2 * (plane.shape[1] // 2)

        rounded = np.floor(blocks + 0.5)

        if np.any((rounded < 0) | (rounded > 255)):
            raise WatermarkError(
                "Internal error: reconstructed pixels exceed uint8."
            )

        offsets = (
            (0, 0),
            (0, 1),
            (1, 0),
            (1, 1),
        )

        for index, (row, column) in enumerate(offsets):
            view = plane[row:height:2, column:width:2]

            view.flat[:len(blocks)] = (
                rounded[:, index].astype(np.uint8)
            )

        return output

    @staticmethod
    def _bits(data: bytes) -> NDArray[np.uint8]:
        bits = np.unpackbits(
            np.frombuffer(data, dtype=np.uint8),
            bitorder="big",
        )

        return np.tile(bits, WatermarkEngine.REPEATS)

    @staticmethod
    def _quantize(
        slots: NDArray,
        bits: NDArray,
        strength: int,
    ) -> NDArray:
        return strength * (
            2 * np.floor(
                (slots / strength - bits) / 2 + 0.5
            )
            + bits
        )

    @staticmethod
    def _decode(
        slots: NDArray,
        byte_count: int,
        strength: int,
    ) -> bytes:
        bits = np.mod(
            np.floor(slots / strength + 0.5),
            2,
        ).astype(np.uint8)

        votes = bits.reshape(
            WatermarkEngine.REPEATS,
            byte_count * 8,
        )

        recovered = (
            votes.sum(axis=0) >= 2
        ).astype(np.uint8)

        return np.packbits(
            recovered,
            bitorder="big",
        ).tobytes()

    @staticmethod
    def psnr(
        original: ImageArray,
        modified: ImageArray,
    ) -> float:
        WatermarkEngine.validate_image(original)
        WatermarkEngine.validate_image(modified)

        if original.shape != modified.shape:
            raise WatermarkError(
                "PSNR requires images with identical shapes."
            )

        difference = (
            original.astype(np.float64)
            - modified.astype(np.float64)
        )

        mse = float(np.mean(difference * difference))

        return (
            math.inf
            if mse == 0
            else 10 * math.log10(255 ** 2 / mse)
        )

    @staticmethod
    def embed(
        cover: ImageArray,
        watermark: ImageArray,
        strength: int = 16,
        size: tuple[int, int] = (32, 32),
    ) -> EmbeddingResult:
        WatermarkEngine.validate_image(cover)

        strength = WatermarkEngine._integer(
            strength, 8, 32, "Strength"
        )

        prepared = WatermarkEngine.prepare_watermark(
            watermark, size
        )

        payload = prepared.tobytes(order="C")
        capacity = WatermarkEngine.capacity_bytes(cover)

        if len(payload) > capacity:
            raise WatermarkError(
                f"Watermark needs {len(payload)} bytes; "
                f"cover holds {capacity}. "
                "Choose a smaller watermark size or a larger cover."
            )

        body = WatermarkEngine.HEADER.pack(
            WatermarkEngine.MAGIC,
            strength,
            WatermarkEngine.REPEATS,
            1,
            0,
            prepared.shape[0],
            prepared.shape[1],
            len(payload),
            zlib.crc32(payload),
        )

        header = body + struct.pack(
            ">I",
            zlib.crc32(body),
        )

        header_bits = WatermarkEngine._bits(header)
        payload_bits = WatermarkEngine._bits(payload)

        used_slots = len(header_bits) + len(payload_bits)

        blocks = WatermarkEngine._blocks(
            cover, used_slots // 2
        )

        # Reserve enough room for both detail coefficients to change safely.
        margin = max(
            strength,
            WatermarkEngine.HEADER_STRENGTH,
        )

        output = cover.copy()
        channel_count = 1 if cover.ndim == 2 else 3

        for channel in range(channel_count):
            blocks = WatermarkEngine._blocks(
                cover, used_slots // 2, channel
            )
            coefficients = HaarTransform.forward(
                np.clip(blocks, margin, 255 - margin)
            )
            slots = coefficients[:, 1:3].ravel().copy()
            split = WatermarkEngine.HEADER_SLOTS

            slots[:split] = WatermarkEngine._quantize(
                slots[:split],
                header_bits,
                WatermarkEngine.HEADER_STRENGTH,
            )
            slots[split:] = WatermarkEngine._quantize(
                slots[split:],
                payload_bits,
                strength,
            )
            coefficients[:, 1:3] = slots.reshape(-1, 2)
            output = WatermarkEngine._write_blocks(
                output,
                HaarTransform.inverse(coefficients),
                channel,
            )

        checked = WatermarkEngine.extract(output)

        if not np.array_equal(
            checked.watermark,
            prepared,
        ):
            raise WatermarkError(
                "The embedding self-check failed."
            )

        return EmbeddingResult(
            output,
            prepared,
            strength,
            WatermarkEngine.psnr(cover, output),
        )

    @staticmethod
    def extract(image: ImageArray) -> ExtractionResult:
        WatermarkEngine.validate_image(image)

        split = WatermarkEngine.HEADER_SLOTS
        available_slots = (
            2
            * (image.shape[0] // 2)
            * (image.shape[1] // 2)
        )

        if available_slots < split:
            raise WatermarkError(
                "The image is too small to contain a watermark header."
            )

        header_blocks = WatermarkEngine._blocks(image, split // 2, 0)
        header_slots = HaarTransform.forward(
            header_blocks
        )[:, 1:3].ravel()

        header = WatermarkEngine._decode(
            header_slots,
            WatermarkEngine.HEADER_BYTES,
            WatermarkEngine.HEADER_STRENGTH,
        )

        body = header[:20]
        stored_header_crc = struct.unpack(
            ">I", header[20:]
        )[0]

        if zlib.crc32(body) != stored_header_crc:
            raise WatermarkError(
                "No valid watermark header was found, or it is damaged."
            )

        (
            magic,
            strength,
            repeats,
            channels,
            flags,
            height,
            width,
            length,
            crc,
        ) = WatermarkEngine.HEADER.unpack(body)

        if (
            magic != WatermarkEngine.MAGIC
            or repeats != 3
            or channels != 1
            or flags != 0
            or not 8 <= strength <= 32
            or not 8 <= height <= 64
            or not 8 <= width <= 64
            or length != height * width
        ):
            raise WatermarkError(
                "The watermark format is invalid or unsupported."
            )

        stop = split + length * 8 * repeats

        if stop > available_slots:
            raise WatermarkError(
                "The watermark is incomplete; "
                "image dimensions may have changed."
            )

        blocks = WatermarkEngine._blocks(image, stop // 2, 0)
        slots = HaarTransform.forward(
            blocks
        )[:, 1:3].ravel()

        payload = WatermarkEngine._decode(
            slots[split:stop],
            length,
            strength,
        )

        if zlib.crc32(payload) != crc:
            raise WatermarkError(
                "Watermark checksum failed. "
                "The embedded data is damaged."
            )

        recovered = (
            np.frombuffer(payload, dtype=np.uint8)
            .reshape(height, width)
            .copy()
        )

        return ExtractionResult(
            recovered,
            strength,
        )
