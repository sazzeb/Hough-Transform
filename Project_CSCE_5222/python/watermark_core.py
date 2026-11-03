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
    verified: bool = True


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
    IMPROVED_MAGIC = b"WVM2"
    SCATTERED = 1
    ADAPTIVE = 2
    DURABLE = 4
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

        scale = min(height / values.shape[0], width / values.shape[1])
        fitted_height = max(1, min(height, round(values.shape[0] * scale)))
        fitted_width = max(1, min(width, round(values.shape[1] * scale)))
        source_rows = np.linspace(0, values.shape[0] - 1, fitted_height)
        source_columns = np.linspace(0, values.shape[1] - 1, fitted_width)
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

        fitted = np.floor(
            top * (1 - row_weight)[:, None]
            + bottom * row_weight[:, None]
            + 0.5
        ).astype(np.uint8)
        prepared = np.full((height, width), 255, dtype=np.uint8)
        top_padding = (height - fitted_height) // 2
        left_padding = (width - fitted_width) // 2
        prepared[
            top_padding:top_padding + fitted_height,
            left_padding:left_padding + fitted_width,
        ] = fitted
        return prepared

    @staticmethod
    def capacity_bytes(image: ImageArray, mode: str = "classic") -> int:
        WatermarkEngine.validate_image(image)

        slots = (
            2
            * (image.shape[0] // 2)
            * (image.shape[1] // 2)
        )

        if mode not in {"classic", "balanced", "durable"}:
            raise WatermarkError("Mode must be classic, balanced or durable.")
        repeats = 5 if mode == "durable" else 3
        return max(0, (slots - WatermarkEngine.HEADER_SLOTS) // (8 * repeats))

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
    def _block_indices(image: ImageArray, count: int) -> NDArray[np.int64]:
        blocks_per_row = image.shape[1] // 2
        available = (image.shape[0] // 2) * blocks_per_row
        header_blocks = WatermarkEngine.HEADER_SLOTS // 2
        remaining = available - header_blocks
        if count > remaining:
            raise WatermarkError("The cover cannot hold this watermark.")
        return header_blocks + np.floor(
            (np.arange(count) + 0.5) * remaining / count
        ).astype(np.int64)

    @staticmethod
    def _selected_blocks(
        image: ImageArray,
        indices: NDArray[np.int64],
        channel: int,
    ) -> NDArray[np.float64]:
        plane = image if image.ndim == 2 else image[:, :, channel]
        columns = plane.shape[1] // 2
        rows = 2 * (indices // columns)
        cols = 2 * (indices % columns)
        return np.column_stack((
            plane[rows, cols], plane[rows, cols + 1],
            plane[rows + 1, cols], plane[rows + 1, cols + 1],
        )).astype(np.float64)

    @staticmethod
    def _write_selected_blocks(
        image: ImageArray,
        indices: NDArray[np.int64],
        blocks: NDArray[np.float64],
        channel: int,
    ) -> None:
        plane = image if image.ndim == 2 else image[:, :, channel]
        columns = plane.shape[1] // 2
        rows = 2 * (indices // columns)
        cols = 2 * (indices % columns)
        rounded = np.floor(blocks + 0.5)
        if np.any((rounded < 0) | (rounded > 255)):
            raise WatermarkError("Reconstructed pixels exceed uint8.")
        plane[rows, cols] = rounded[:, 0].astype(np.uint8)
        plane[rows, cols + 1] = rounded[:, 1].astype(np.uint8)
        plane[rows + 1, cols] = rounded[:, 2].astype(np.uint8)
        plane[rows + 1, cols + 1] = rounded[:, 3].astype(np.uint8)

    @staticmethod
    def _adaptive_strengths(
        coefficients: NDArray[np.float64], strength: int
    ) -> NDArray[np.int64]:
        quiet_strength = max(8, int(math.floor(0.75 * strength + 0.5)))
        return np.where(
            np.abs(coefficients[:, 3]) < 16,
            quiet_strength,
            strength,
        )

    @staticmethod
    def _stabilize_adaptive_details(
        coefficients: NDArray[np.float64], quiet: NDArray[np.bool_]
    ) -> None:
        """Keep the texture decision stable after inverse transform rounding."""
        details = coefficients[:, 3]
        details[quiet] = np.clip(details[quiet], -12, 12)
        textured = ~quiet
        details[textured] = np.sign(details[textured]) * np.maximum(
            np.abs(details[textured]), 20
        )

    @staticmethod
    def _decode_channels(channels: list[bytes]) -> bytes:
        if len(channels) == 1:
            return channels[0]
        bits = np.stack([
            np.unpackbits(np.frombuffer(data, dtype=np.uint8))
            for data in channels
        ])
        return np.packbits((bits.sum(axis=0) >= 2).astype(np.uint8)).tobytes()

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
        mode: str = "classic",
    ) -> EmbeddingResult:
        WatermarkEngine.validate_image(cover)

        strength = WatermarkEngine._integer(
            strength, 8, 32, "Strength"
        )

        prepared = WatermarkEngine.prepare_watermark(
            watermark, size
        )

        if mode in {"balanced", "durable"}:
            return WatermarkEngine._embed_improved(
                cover, prepared, strength, mode
            )
        if mode != "classic":
            raise WatermarkError("Mode must be classic, balanced or durable.")

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
    def _embed_improved(
        cover: ImageArray,
        prepared: ImageArray,
        strength: int,
        mode: str,
    ) -> EmbeddingResult:
        repeats = 5 if mode == "durable" else 3
        flags = (
            WatermarkEngine.SCATTERED
            | WatermarkEngine.ADAPTIVE
            | (WatermarkEngine.DURABLE if mode == "durable" else 0)
        )
        payload = prepared.tobytes(order="C")
        payload_bits = np.tile(
            np.unpackbits(np.frombuffer(payload, dtype=np.uint8)),
            repeats,
        )
        available = (cover.shape[0] // 2) * (cover.shape[1] // 2)
        payload_blocks = len(payload_bits) // 2
        if payload_blocks > available - WatermarkEngine.HEADER_SLOTS // 2:
            raise WatermarkError(
                "The cover cannot hold this watermark. "
                "Choose a smaller watermark size or a larger cover."
            )
        header_body = WatermarkEngine.HEADER.pack(
            WatermarkEngine.IMPROVED_MAGIC, strength, repeats, 1,
            flags, prepared.shape[0], prepared.shape[1],
            len(payload), zlib.crc32(payload),
        )
        header = header_body + struct.pack(">I", zlib.crc32(header_body))
        header_bits = WatermarkEngine._bits(header)
        header_indices = np.arange(WatermarkEngine.HEADER_SLOTS // 2)
        payload_indices = WatermarkEngine._block_indices(
            cover, payload_blocks
        )
        output = cover.copy()
        channels = 1 if cover.ndim == 2 else 3
        margin = max(strength, WatermarkEngine.HEADER_STRENGTH) + 8
        for channel in range(channels):
            header_blocks = WatermarkEngine._selected_blocks(
                cover, header_indices, channel
            )
            header_coefficients = HaarTransform.forward(
                np.clip(header_blocks, margin, 255 - margin)
            )
            header_slots = header_coefficients[:, 1:3].ravel()
            header_coefficients[:, 1:3] = WatermarkEngine._quantize(
                header_slots, header_bits,
                WatermarkEngine.HEADER_STRENGTH,
            ).reshape(-1, 2)
            WatermarkEngine._write_selected_blocks(
                output, header_indices,
                HaarTransform.inverse(header_coefficients), channel,
            )

            payload_blocks_data = WatermarkEngine._selected_blocks(
                cover, payload_indices, channel
            )
            payload_coefficients = HaarTransform.forward(
                np.clip(payload_blocks_data, margin, 255 - margin)
            )
            local_strength = WatermarkEngine._adaptive_strengths(
                payload_coefficients, strength
            )
            WatermarkEngine._stabilize_adaptive_details(
                payload_coefficients,
                np.abs(payload_coefficients[:, 3]) < 16,
            )
            slot_strength = np.repeat(local_strength, 2)
            payload_slots = payload_coefficients[:, 1:3].ravel()
            payload_coefficients[:, 1:3] = WatermarkEngine._quantize(
                payload_slots, payload_bits, slot_strength
            ).reshape(-1, 2)
            WatermarkEngine._write_selected_blocks(
                output, payload_indices,
                HaarTransform.inverse(payload_coefficients), channel,
            )

        recovered = WatermarkEngine.extract(output)
        if not np.array_equal(recovered.watermark, prepared):
            raise WatermarkError("The embedding self-check failed.")
        return EmbeddingResult(
            output, prepared, strength,
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

        channels = 1 if image.ndim == 2 else 3
        header_copies = []
        for channel in range(channels):
            header_blocks = WatermarkEngine._blocks(
                image, split // 2, channel
            )
            header_slots = HaarTransform.forward(
                header_blocks
            )[:, 1:3].ravel()
            header_copies.append(WatermarkEngine._decode(
                header_slots, WatermarkEngine.HEADER_BYTES,
                WatermarkEngine.HEADER_STRENGTH,
            ))
        header = WatermarkEngine._decode_channels(header_copies)

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
            encoded_channels,
            flags,
            height,
            width,
            length,
            crc,
        ) = WatermarkEngine.HEADER.unpack(body)

        if (
            magic not in {WatermarkEngine.MAGIC, WatermarkEngine.IMPROVED_MAGIC}
            or repeats not in {3, 5}
            or encoded_channels != 1
            or (
                (magic == WatermarkEngine.MAGIC and (repeats != 3 or flags != 0))
                or (magic == WatermarkEngine.IMPROVED_MAGIC and
                    flags != (WatermarkEngine.SCATTERED | WatermarkEngine.ADAPTIVE |
                              (WatermarkEngine.DURABLE if repeats == 5 else 0)))
            )
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

        payload_copies = []
        if magic == WatermarkEngine.IMPROVED_MAGIC:
            indices = WatermarkEngine._block_indices(
                image, length * 8 * repeats // 2
            )
            for channel in range(channels):
                blocks = WatermarkEngine._selected_blocks(
                    image, indices, channel
                )
                coefficients = HaarTransform.forward(blocks)
                slot_strength = np.repeat(
                    WatermarkEngine._adaptive_strengths(
                        coefficients, strength
                    ), 2,
                )
                bits = np.mod(
                    np.floor(coefficients[:, 1:3].ravel()
                             / slot_strength + 0.5), 2,
                ).astype(np.uint8)
                votes = bits.reshape(repeats, length * 8)
                payload_copies.append(np.packbits(
                    (votes.sum(axis=0) >= repeats // 2 + 1).astype(np.uint8)
                ).tobytes())
        else:
            for channel in range(channels):
                blocks = WatermarkEngine._blocks(
                    image, stop // 2, channel
                )
                slots = HaarTransform.forward(
                    blocks
                )[:, 1:3].ravel()
                payload_copies.append(WatermarkEngine._decode(
                    slots[split:stop], length, strength,
                ))
        payload = WatermarkEngine._decode_channels(payload_copies)

        verified = zlib.crc32(payload) == crc
        if not verified and not (
            magic == WatermarkEngine.IMPROVED_MAGIC
            and flags & WatermarkEngine.DURABLE
        ):
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
            verified,
        )
