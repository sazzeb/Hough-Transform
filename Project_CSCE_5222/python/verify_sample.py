"""Verify the supplied photo through embedding, PNG storage, and extraction."""

from pathlib import Path

import numpy as np

from image_io import ImageStore
from sample_data import load_sample_images
from watermark_core import WatermarkEngine


def main() -> None:
    """Embed and save a sample, then check its recovered watermark."""
    folder = Path(__file__).resolve().parent
    cover, watermark = load_sample_images()
    result = WatermarkEngine.embed(cover, watermark)

    output_folder = folder / "sample_outputs"
    output_folder.mkdir(exist_ok=True)

    cover_path = ImageStore.save_png(output_folder / "cover.png", cover)
    watermarked_path = ImageStore.save_png(
        output_folder / "watermarked.png", result.image
    )
    saved_image = ImageStore.read(watermarked_path, watermarked=True)
    recovered = WatermarkEngine.extract(saved_image)
    extracted_path = ImageStore.save_png(
        output_folder / "extracted.png", recovered.watermark
    )

    if not np.array_equal(saved_image, result.image):
        raise AssertionError("The saved PNG changed the watermarked pixels.")

    if not np.array_equal(recovered.watermark, result.prepared_watermark):
        raise AssertionError("The prepared watermark was not recovered exactly.")

    if recovered.strength != result.strength:
        raise AssertionError("The stored strength was not recovered.")

    if not np.array_equal(saved_image[:, :, :2], cover[:, :, :2]):
        raise AssertionError("The red or green channel changed.")

    blocks_per_row = cover.shape[1] // 2
    used_blocks = (
        WatermarkEngine.HEADER_SLOTS
        + result.prepared_watermark.size * 8 * WatermarkEngine.REPEATS
    ) // 2
    modified_rows = 2 * (
        (used_blocks + blocks_per_row - 1) // blocks_per_row
    )
    strip_psnr = WatermarkEngine.psnr(
        cover[:modified_rows], saved_image[:modified_rows]
    )

    print(f"Cover: {cover.shape[1]} x {cover.shape[0]} RGB")
    print(f"Capacity: {WatermarkEngine.capacity_bytes(cover)} bytes")
    print(
        "Recovered exactly: "
        f"{recovered.watermark.shape[1]} x {recovered.watermark.shape[0]} "
        "grayscale watermark"
    )
    print(f"Strength: {recovered.strength}")
    print(f"Global PSNR: {result.psnr:.2f} dB")
    print(f"Top {modified_rows} rows PSNR: {strip_psnr:.2f} dB")
    print(f"Decoded cover PNG: {cover_path}")
    print(f"Watermarked PNG: {watermarked_path}")
    print(f"Extracted PNG: {extracted_path}")


if __name__ == "__main__":
    main()
