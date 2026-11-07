from pathlib import Path
import gc
import io
import random
import tempfile
import time
import tkinter as tk
import unittest
from unittest.mock import patch

import numpy as np
from PIL import Image

from image_io import ImageStore
from sample_data import ExampleGallery, load_example_images
from watermark_app import WatermarkApp
from watermark_core import (
    HaarTransform,
    WatermarkEngine,
    WatermarkError,
)


class EngineTests(unittest.TestCase):
    def setUp(self):
        self.random = np.random.default_rng(42)

        self.mark = self.random.integers(
            0,
            256,
            (37, 49, 3),
            dtype=np.uint8,
        )

    def test_haar_inverse(self):
        blocks = self.random.integers(
            0,
            256,
            (1000, 4),
        ).astype(np.float64)

        np.testing.assert_array_equal(
            HaarTransform.inverse(
                HaarTransform.forward(blocks)
            ),
            blocks,
        )

    def test_evaluation_metrics_have_known_reference_values(self):
        cover = np.full((8, 8, 3), 100, dtype=np.uint8)
        self.assertEqual(WatermarkEngine.ssim(cover, cover), 1.0)
        self.assertEqual(WatermarkEngine.psnr(cover, cover), float("inf"))
        changed = np.full((8, 8, 3), 110, dtype=np.uint8)
        self.assertAlmostEqual(
            WatermarkEngine.psnr(cover, changed),
            20 * np.log10(255 / 10),
        )
        self.assertLess(WatermarkEngine.ssim(cover, changed), 1.0)
        original = np.array([[1, 0]], dtype=np.uint8)
        recovered = np.array([[1, 1]], dtype=np.uint8)
        self.assertAlmostEqual(
            WatermarkEngine.bit_error_rate(original, recovered), 1 / 16
        )
        self.assertAlmostEqual(
            WatermarkEngine.normalized_correlation(original, recovered),
            1 / np.sqrt(2),
        )
        self.assertTrue(np.isnan(WatermarkEngine.normalized_correlation(
            np.zeros((1, 2), dtype=np.uint8), recovered
        )))

    def test_robustness_study_reports_exact_and_unreadable_cases(self):
        cover = np.full((192, 192), 128, dtype=np.uint8)
        watermark = np.arange(256, dtype=np.uint8).reshape(16, 16)
        report = WatermarkEngine.evaluate_robustness(cover, watermark)
        self.assertEqual(len(report["details"]), 72)
        self.assertEqual(len(report["summary"]), 24)
        self.assertEqual(report["skipped"], 18)
        unchanged = [
            row for row in report["details"]
            if row[3] == "Unchanged PNG"
        ]
        self.assertTrue(all(row[4] == "Verified exact" for row in unchanged))
        self.assertTrue(all(row[7] == 0 for row in unchanged))
        self.assertTrue(all(row[2] == 16 for row in report["details"]))
        self.assertTrue(all(0 <= row[4] <= 1 for row in report["summary"]))

    def test_improved_modes_preserve_shape_and_recover_from_channel_damage(self):
        wide_mark = np.full((16, 32), 70, dtype=np.uint8)
        fitted = WatermarkEngine.prepare_watermark(wide_mark, (32, 32))
        self.assertTrue(np.all(fitted[:8] == 255))
        self.assertTrue(np.all(fitted[8:24] == 70))

        cover = np.full((512, 512, 3), 128, dtype=np.uint8)
        for mode in ("balanced", "durable"):
            with self.subTest(mode=mode):
                result = WatermarkEngine.embed(
                    cover, wide_mark, 24, (32, 32), mode
                )
                damaged = result.image.copy()
                damaged[:, :, 0] = cover[:, :, 0]
                recovered = WatermarkEngine.extract(damaged)
                np.testing.assert_array_equal(
                    recovered.watermark, result.prepared_watermark
                )
                changed_rows = np.flatnonzero(
                    np.any(result.image != cover, axis=(1, 2))
                )
                self.assertGreater(changed_rows.max(), 400)

    def test_balanced_fixture_matches_matlab(self):
        cover = np.full((512, 512, 3), 128, dtype=np.uint8)
        mark = np.arange(256, dtype=np.uint8).reshape(16, 16)
        result = WatermarkEngine.embed(
            cover, mark, 16, (16, 16), "balanced"
        )
        values = result.image.astype(np.float64).ravel()
        self.assertEqual(int(values.sum()), 100663296)
        self.assertEqual(int((values * values).sum()), 12886360320)
        self.assertEqual(
            int((values * np.arange(1, values.size + 1)).sum() % 2**32),
            4252447456,
        )

    def test_durable_mode_reports_lossy_edit_limits(self):
        cover = self.random.integers(
            0, 256, (512, 512, 3), dtype=np.uint8
        )
        mark = np.arange(256, dtype=np.uint8).reshape(16, 16)
        embedded = WatermarkEngine.embed(
            cover, mark, 32, (16, 16), "durable"
        ).image

        jpeg_bytes = io.BytesIO()
        Image.fromarray(embedded).save(
            jpeg_bytes, format="JPEG", quality=95
        )
        jpeg_bytes.seek(0)
        with Image.open(jpeg_bytes) as compressed:
            jpeg_image = np.asarray(compressed).copy()
        resized = np.asarray(
            Image.fromarray(embedded).resize(
                (500, 500), Image.Resampling.LANCZOS
            )
        )
        cropped = embedded[16:-16, 16:-16]
        with self.assertRaises(WatermarkError):
            WatermarkEngine.extract(jpeg_image)
        with self.assertRaises(WatermarkError):
            WatermarkEngine.extract(resized)
        with self.assertRaises(WatermarkError):
            WatermarkEngine.extract(cropped)

    def test_durable_mode_marks_uncorrectable_payload_as_approximate(self):
        cover = np.full((512, 512), 128, np.uint8)
        mark = np.arange(256, dtype=np.uint8).reshape(16, 16)
        embedded = WatermarkEngine.embed(
            cover, mark, 32, (16, 16), "durable"
        ).image
        altered = embedded.copy()
        payload_bits_per_copy = mark.size * 8
        indices = WatermarkEngine._block_indices(
            embedded, payload_bits_per_copy * 5 // 2
        )
        for copy in range(3):
            block_index = indices[copy * payload_bits_per_copy // 2]
            block = WatermarkEngine._selected_blocks(
                altered, np.array([block_index]), 0
            )
            coefficients = HaarTransform.forward(block)
            coefficients[:, 1] += 24
            WatermarkEngine._write_selected_blocks(
                altered, np.array([block_index]),
                HaarTransform.inverse(coefficients), 0,
            )
        recovered = WatermarkEngine.extract(altered)
        self.assertFalse(recovered.verified)
        self.assertNotEqual(
            recovered.watermark.tobytes(), mark.tobytes()
        )

    def test_prefix_blocks_match_the_full_image(self):
        image = self.random.integers(
            0, 256, (257, 259, 3), dtype=np.uint8
        )
        full = WatermarkEngine._blocks(image)

        for count in (0, 1, 129, 288, len(full)):
            with self.subTest(count=count):
                np.testing.assert_array_equal(
                    WatermarkEngine._blocks(image, count),
                    full[:count],
                )

        self.assertEqual(
            WatermarkEngine._blocks(
                np.zeros((1, 1), dtype=np.uint8)
            ).shape,
            (0, 4),
        )

    def test_all_strengths_and_extreme_images(self):
        cases = 0

        shapes = (
            (256, 256),
            (257, 259, 3),
            (512, 512, 3),
        )

        for shape in shapes:
            checker = (
                np.indices(shape[:2]).sum(axis=0)
                % 2
                * 255
            ).astype(np.uint8)

            if len(shape) == 3:
                checker = np.repeat(
                    checker[:, :, None],
                    3,
                    axis=2,
                )

            covers = (
                np.zeros(shape, np.uint8),
                np.full(shape, 255, np.uint8),
                checker,
                self.random.integers(
                    0,
                    256,
                    shape,
                    dtype=np.uint8,
                ),
            )

            for strength in range(8, 33):
                for cover in covers:
                    with self.subTest(
                        shape=shape,
                        strength=strength,
                        case=cases,
                    ):
                        original = cover.copy()

                        result = WatermarkEngine.embed(
                            cover,
                            self.mark,
                            strength,
                        )

                        recovered = WatermarkEngine.extract(
                            result.image
                        )

                        np.testing.assert_array_equal(
                            recovered.watermark,
                            result.prepared_watermark,
                        )

                        np.testing.assert_array_equal(
                            cover,
                            original,
                        )

                        self.assertEqual(
                            recovered.strength,
                            strength,
                        )

                        self.assertEqual(
                            result.image.dtype,
                            np.uint8,
                        )

                        self.assertEqual(
                            result.image.shape,
                            cover.shape,
                        )

                        if cover.ndim == 3:
                            self.assertGreater(
                                np.count_nonzero(result.image != cover),
                                0,
                            )

                        if shape[0] % 2:
                            np.testing.assert_array_equal(
                                result.image[-1],
                                cover[-1],
                            )

                        if shape[1] % 2:
                            np.testing.assert_array_equal(
                                result.image[:, -1],
                                cover[:, -1],
                            )

                        cases += 1

        self.assertEqual(cases, 300)

    def test_sizes_and_capacity(self):
        sizes = (
            (8, 8),
            (8, 31),
            (24, 24),
            (32, 32),
            (64, 64),
        )

        for size in sizes:
            result = WatermarkEngine.embed(
                np.full((512, 512), 127, np.uint8),
                self.mark,
                11,
                size,
            )

            self.assertEqual(
                result.prepared_watermark.shape,
                size,
            )

        exact = np.full(
            (66, 64),
            128,
            np.uint8,
        )

        self.assertEqual(
            WatermarkEngine.capacity_bytes(exact),
            64,
        )

        result = WatermarkEngine.embed(
            exact,
            self.mark,
            16,
            (8, 8),
        )

        self.assertEqual(
            result.prepared_watermark.shape,
            (8, 8),
        )

        with self.assertRaises(WatermarkError):
            WatermarkEngine.embed(
                np.zeros((64, 64), np.uint8),
                self.mark,
                16,
                (8, 8),
            )

    def test_invalid_inputs_and_options(self):
        cover = np.full(
            (256, 256),
            128,
            np.uint8,
        )

        invalid_images = (
            np.zeros((0, 2), np.uint8),
            np.zeros((5, 5), float),
            np.zeros((5, 5, 4), np.uint8),
            np.zeros((1,), np.uint8),
            None,
        )

        for image in invalid_images:
            with self.subTest(image_type=type(image)):
                with self.assertRaises(WatermarkError):
                    WatermarkEngine.embed(
                        image,
                        self.mark,
                    )

        strengths = (
            0,
            7,
            33,
            True,
            8.5,
            float("nan"),
            float("inf"),
            "16",
        )

        for strength in strengths:
            with self.assertRaises(WatermarkError):
                WatermarkEngine.embed(
                    cover,
                    self.mark,
                    strength,
                )

        sizes = (
            (7, 8),
            (65, 8),
            (8.1, 8),
            (8,),
            "32",
        )

        for size in sizes:
            with self.assertRaises(WatermarkError):
                WatermarkEngine.embed(
                    cover,
                    self.mark,
                    size=size,
                )

        large = np.zeros((2_000, 2_500), np.uint8)
        WatermarkEngine.validate_image(large)

    def test_no_watermark_and_too_small(self):
        for shape in (
            (1, 1),
            (16, 16),
            (256, 256),
        ):
            with self.assertRaises(WatermarkError):
                WatermarkEngine.extract(
                    np.zeros(shape, np.uint8)
                )

    @staticmethod
    def flip_slots(image, positions, strength):
        coefficients = HaarTransform.forward(
            WatermarkEngine._blocks(image)
        )

        slots = coefficients[:, 1:3].ravel().copy()
        slots[list(positions)] += strength

        coefficients[:, 1:3] = slots.reshape(-1, 2)

        return WatermarkEngine._write_blocks(
            image,
            HaarTransform.inverse(coefficients),
        )

    def test_repetition_repairs_one_copy(self):
        result = WatermarkEngine.embed(
            np.full((256, 256), 128, np.uint8),
            self.mark,
        )

        altered = self.flip_slots(
            result.image,
            [0, WatermarkEngine.HEADER_SLOTS],
            16,
        )

        recovered = WatermarkEngine.extract(altered)

        np.testing.assert_array_equal(
            recovered.watermark,
            result.prepared_watermark,
        )

    def test_payload_damage_is_detected(self):
        result = WatermarkEngine.embed(
            np.full((256, 256), 128, np.uint8),
            self.mark,
        )

        start = WatermarkEngine.HEADER_SLOTS
        bits_per_copy = result.prepared_watermark.size * 8

        altered = self.flip_slots(
            result.image,
            [start, start + bits_per_copy],
            16,
        )

        with self.assertRaisesRegex(
            WatermarkError,
            "checksum",
        ):
            WatermarkEngine.extract(altered)

    def test_header_damage_is_detected(self):
        result = WatermarkEngine.embed(
            np.full((256, 256), 128, np.uint8),
            self.mark,
        )

        altered = self.flip_slots(
            result.image,
            [0, 24 * 8],
            16,
        )

        with self.assertRaisesRegex(
            WatermarkError,
            "header",
        ):
            WatermarkEngine.extract(altered)

    def test_incomplete_image_is_rejected(self):
        result = WatermarkEngine.embed(
            np.full((256, 256), 128, np.uint8),
            self.mark,
        )

        with self.assertRaises(WatermarkError):
            WatermarkEngine.extract(
                result.image[:100]
            )

    def test_golden_vector(self):
        cover = (
            (np.arange(65536) % 256)
            .astype(np.uint8)
            .reshape(256, 256)
        )

        mark = np.arange(
            64,
            dtype=np.uint8,
        ).reshape(8, 8)

        result = WatermarkEngine.embed(
            cover,
            mark,
            12,
            (8, 8),
        )

        values = result.image.ravel().astype(np.float64)

        self.assertEqual(
            int(values.sum()),
            8357952,
        )

        self.assertEqual(
            int(
                (
                    values * np.arange(1, 65537)
                ).sum() % 2**32
            ),
            3586566448,
        )

        self.assertEqual(
            int((values * values).sum()),
            1422849056,
        )

        self.assertTrue(
            np.isinf(
                WatermarkEngine.psnr(cover, cover)
            )
        )


class StorageTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.path = Path(self.folder.name)

    def tearDown(self):
        self.folder.cleanup()

    def test_png_round_trip(self):
        random = np.random.default_rng(7)

        mark = random.integers(
            0,
            256,
            (32, 32),
            dtype=np.uint8,
        )

        for shape in (
            (256, 256),
            (257, 259, 3),
        ):
            cover = random.integers(
                0,
                256,
                shape,
                dtype=np.uint8,
            )

            result = WatermarkEngine.embed(
                cover,
                mark,
            )

            path = ImageStore.save_png(
                self.path / "result.png",
                result.image,
            )

            reloaded = ImageStore.read(
                path,
                watermarked=True,
            )

            np.testing.assert_array_equal(
                reloaded,
                result.image,
            )

            np.testing.assert_array_equal(
                WatermarkEngine.extract(reloaded).watermark,
                mark,
            )

            ImageStore.save_png(
                self.path / "extracted.png",
                mark,
            )

            np.testing.assert_array_equal(
                ImageStore.read(
                    self.path / "extracted.png"
                ),
                mark,
            )

    def test_palette_transparency_and_binary(self):
        palette = Image.new(
            "P",
            (8, 8),
            0,
        )

        palette.putpalette(
            [255, 0, 0] + [0, 0, 0] * 255
        )

        palette.save(
            self.path / "palette.png",
            transparency=0,
        )

        image = ImageStore.read(
            self.path / "palette.png"
        )

        np.testing.assert_array_equal(
            image,
            np.full((8, 8, 3), 255, np.uint8),
        )

        rgba = Image.new(
            "RGBA",
            (8, 8),
            (100, 150, 200, 128),
        )

        rgba.save(self.path / "alpha.png")

        self.assertEqual(
            ImageStore.read(
                self.path / "alpha.png"
            )[0, 0].tolist(),
            [177, 202, 227],
        )

        Image.new(
            "1",
            (8, 8),
            1,
        ).save(self.path / "binary.png")

        self.assertTrue(
            np.all(
                ImageStore.read(
                    self.path / "binary.png"
                ) == 255
            )
        )

    def test_rejected_files(self):
        (self.path / "broken.png").write_bytes(
            b"not an image"
        )

        with self.assertRaises(OSError):
            ImageStore.read(
                self.path / "broken.png"
            )

        for mode, name in (
            ("I;16", "high.png"),
            ("RGBA", "alpha.png"),
        ):
            Image.new(
                mode,
                (8, 8),
            ).save(self.path / name)

            with self.assertRaises(WatermarkError):
                ImageStore.read(
                    self.path / name,
                    watermarked=True,
                )

        with self.assertRaises(WatermarkError):
            ImageStore.read(
                self.path / "high.png"
            )

        Image.new(
            "RGB",
            (8, 8),
        ).save(self.path / "photo.jpg")

        with self.assertRaises(WatermarkError):
            ImageStore.read(
                self.path / "photo.jpg",
                watermarked=True,
            )

        with self.assertRaises(WatermarkError):
            ImageStore.save_png(
                self.path / "bad.jpg",
                np.zeros((8, 8), np.uint8),
            )

    def test_large_inputs_are_resized_without_changing_the_source(self):
        path = self.path / "small.png"
        Image.new("RGB", (8, 8), (20, 40, 60)).save(path)

        with patch.object(ImageStore, "MAX_WORKING_PIXELS", 16):
            resized = ImageStore.read(path)

        self.assertLessEqual(resized.shape[0] * resized.shape[1], 16)
        with Image.open(path) as original:
            self.assertEqual(original.size, (8, 8))

    def test_source_safety_limit_is_checked_before_decoding(self):
        path = self.path / "small.png"
        Image.new("RGB", (4, 4)).save(path)

        with patch.object(ImageStore, "MAX_SOURCE_PIXELS", 10):
            with self.assertRaisesRegex(
                WatermarkError, "safety limit"
            ):
                ImageStore.read(path)

    def test_oversized_original_is_not_treated_as_a_saved_watermark(self):
        path = self.path / "original.png"
        Image.new("RGB", (4, 4)).save(path)

        with patch.object(ImageStore, "MAX_WATERMARKED_PIXELS", 10):
            with self.assertRaisesRegex(
                WatermarkError, "Save watermarked PNG"
            ):
                ImageStore.read(path, watermarked=True)

    def test_failed_save_preserves_existing_file(self):
        target = self.path / "existing.png"

        original = np.full(
            (8, 8),
            31,
            np.uint8,
        )

        ImageStore.save_png(target, original)

        with patch(
            "image_io.os.replace",
            side_effect=OSError("simulated write failure"),
        ):
            with self.assertRaises(OSError):
                ImageStore.save_png(
                    target,
                    np.full((8, 8), 99, np.uint8),
                )

        np.testing.assert_array_equal(
            ImageStore.read(target),
            original,
        )

        self.assertEqual(
            list(self.path.glob(".watermark-*")),
            [],
        )


class ExampleGalleryTests(unittest.TestCase):
    def test_every_photo_loads_and_recovers_in_a_shuffled_round(self):
        gallery = ExampleGallery(rng=random.Random(7))
        self.assertGreaterEqual(len(gallery.entries), 10)
        previous = None

        for round_number in range(2):
            seen = set()
            for _ in gallery.entries:
                example = gallery.next_example()
                cover_path = example["cover_path"]
                self.assertNotEqual(cover_path, previous)
                self.assertNotEqual(cover_path, example["watermark_path"])
                self.assertTrue(cover_path.is_file())
                self.assertTrue(example["watermark_path"].is_file())
                self.assertTrue(example["cover_source"].startswith(
                    "https://unsplash.com/photos/"
                ))
                seen.add(cover_path)
                previous = cover_path

                if round_number == 0:
                    cover, mark = load_example_images(example)
                    self.assertEqual(cover.shape, (768, 1152, 3))
                    self.assertEqual(mark.shape, (96, 96))
                    for mode in ("classic", "balanced", "durable"):
                        for strength in (8, 16, 32):
                            with self.subTest(
                                photo=example["title"], mode=mode,
                                strength=strength,
                            ):
                                embedded = WatermarkEngine.embed(
                                    cover, mark, strength, (32, 32), mode
                                )
                                extracted = WatermarkEngine.extract(
                                    embedded.image
                                )
                                self.assertTrue(extracted.verified)
                                np.testing.assert_array_equal(
                                    extracted.watermark,
                                    embedded.prepared_watermark,
                                )

            self.assertEqual(len(seen), len(gallery.entries))


class GuiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        try:
            cls.master = tk.Tk()

        except tk.TclError as error:
            raise unittest.SkipTest(
                f"A graphical display is required: {error}"
            ) from error

        cls.master.withdraw()

    @classmethod
    def tearDownClass(cls):
        cls.master.destroy()

    def setUp(self):
        self.root = self.master
        self.root.withdraw()
        self.app = WatermarkApp(self.root)

        self.folder = tempfile.TemporaryDirectory()
        self.path = Path(self.folder.name)

    def tearDown(self):
        if hasattr(self, "app"):
            self.app.executor.shutdown(
                wait=True,
                cancel_futures=True,
            )

            for child in self.root.winfo_children():
                child.destroy()
            self.folder.cleanup()
            self.app = None
            self.root = None
            gc.collect()

    def finish(self):
        deadline = time.monotonic() + 15

        while (
            self.app.busy
            and time.monotonic() < deadline
        ):
            self.root.update()
            time.sleep(0.01)

        self.assertFalse(
            self.app.busy,
            "The GUI operation did not complete.",
        )

        self.root.update()

    def test_complete_workflow(self):
        cover = np.full(
            (256, 256, 3),
            128,
            np.uint8,
        )

        mark = (
            np.arange(1024, dtype=np.int64)
            .reshape(32, 32)
            .astype(np.uint8)
        )

        Image.fromarray(cover).save(
            self.path / "cover.png"
        )

        Image.fromarray(mark).save(
            self.path / "mark.png"
        )

        with patch(
            "watermark_app.messagebox.showerror"
        ) as error:
            inputs = (
                ("cover", "cover.png"),
                ("watermark", "mark.png"),
            )

            for name, filename in inputs:
                with patch(
                    "watermark_app.filedialog.askopenfilename",
                    return_value=str(self.path / filename),
                ):
                    self.app.load(name)
                    self.finish()

            self.app.embed()
            self.finish()

            self.assertEqual(self.app.metric_values["ber"]["text"], "0.000%")
            self.assertEqual(self.app.metric_values["ncc"]["text"], "1.00000")
            self.assertIn("dB", self.app.metric_values["psnr"]["text"])
            self.assertNotEqual(
                self.app.metric_values["ssim"]["text"],
                "Need both images",
            )

            self.assertIn(
                "Verified exact",
                self.app.status.get(),
            )

            np.testing.assert_array_equal(
                self.app.images["extracted"], mark
            )

            self.app.strength.set("32")

            self.app.extract()
            self.finish()

            np.testing.assert_array_equal(
                self.app.images["extracted"],
                mark,
            )

            for name in (
                "watermarked",
                "extracted",
            ):
                with patch(
                    "watermark_app.filedialog.asksaveasfilename",
                    return_value=str(
                        self.path / f"{name}.png"
                    ),
                ):
                    self.app.save(name)
                    self.finish()

            with patch(
                "watermark_app.filedialog.askopenfilename",
                return_value=str(
                    self.path / "watermarked.png"
                ),
            ):
                self.app.load("watermarked")
                self.finish()

            np.testing.assert_array_equal(
                self.app.images["extracted"], mark
            )

            self.assertEqual(
                self.app.metric_values["psnr"]["text"],
                "Reference unavailable",
            )
            self.assertEqual(
                self.app.metric_values["ber"]["text"],
                "Reference unavailable",
            )

            self.app.extract()
            self.finish()

            np.testing.assert_array_equal(
                self.app.images["extracted"],
                mark,
            )

            error.assert_not_called()

    def test_strength_slider_previews_and_commits_full_image(self):
        cover = np.full((768, 768, 3), 128, np.uint8)
        mark = np.full((16, 16), 80, np.uint8)
        self.app.images["cover"] = cover
        self.app.images["watermark"] = mark
        self.app._show("cover", cover)
        self.app._show("watermark", mark)
        self.app._strength_drag("75")
        self.assertEqual(
            self.app.metric_values["ber"]["text"], "Need both marks"
        )
        deadline = time.monotonic() + 5
        while self.app.preview_job is not None and time.monotonic() < deadline:
            self.root.update()
            time.sleep(0.01)
        self.finish()
        self.assertTrue(self.app.preview_only)
        self.assertEqual(self.app.images["watermarked"].shape[:2], (640, 640))
        self.assertEqual(self.app.metric_values["ber"]["text"], "0.000%")
        self.assertEqual(str(self.app.buttons["save_image"]["state"]), "disabled")
        self.app._strength_release(None)
        self.finish()
        self.assertFalse(self.app.preview_only)
        self.assertEqual(self.app.images["watermarked"].shape[:2], (768, 768))
        self.assertEqual(str(self.app.buttons["save_image"]["state"]), "normal")

    def test_example_and_failed_reload_keep_the_previous_result(self):
        with patch("watermark_app.messagebox.showerror") as error:
            self.app.try_sample()
            self.finish()

            cover = self.app.images["cover"]
            watermark = self.app.images["watermark"]
            watermarked = self.app.images["watermarked"].copy()
            expected = WatermarkEngine.prepare_watermark(
                watermark
            )

            self.assertEqual(cover.shape, (768, 1152, 3))
            self.assertEqual(watermark.shape, (96, 96))
            np.testing.assert_array_equal(
                self.app.images["extracted"], expected
            )
            self.assertIn("Verified exact", self.app.status.get())
            first_cover = self.app.current_example["cover_path"]
            self.app.try_sample()
            self.finish()
            self.assertNotEqual(
                self.app.current_example["cover_path"], first_cover
            )
            watermarked = self.app.images["watermarked"].copy()
            expected = self.app.images["extracted"].copy()

            invalid = self.path / "plain.png"
            Image.new("L", (256, 256), 128).save(invalid)

            with patch(
                "watermark_app.filedialog.askopenfilename",
                return_value=str(invalid),
            ):
                self.app.load("watermarked")
                self.finish()

            np.testing.assert_array_equal(
                self.app.images["watermarked"], watermarked
            )
            np.testing.assert_array_equal(
                self.app.images["extracted"], expected
            )
            error.assert_called_once()
            self.assertIn("Save watermarked PNG", error.call_args.args[1])

    def test_example_button_completes_a_full_shuffled_round(self):
        self.app.example_gallery = ExampleGallery(rng=random.Random(7))
        seen = set()
        with patch("watermark_app.messagebox.showerror") as error:
            for _ in self.app.example_gallery.entries:
                self.app.try_sample()
                self.finish()
                seen.add(self.app.current_example["cover_path"])
                self.assertTrue(self.app.recovery_verified)
                self.assertIn("Verified exact", self.app.status.get())

        self.assertEqual(len(seen), len(self.app.example_gallery.entries))
        error.assert_not_called()

    def test_evaluation_tables_use_the_selected_image_pair(self):
        self.app.images["cover"] = np.full((192, 192), 128, dtype=np.uint8)
        self.app.images["watermark"] = np.arange(
            256, dtype=np.uint8
        ).reshape(16, 16)
        self.app._update_controls()
        self.app.run_evaluation()
        self.finish()
        self.assertEqual(len(self.app.study_summary.get_children()), 24)
        self.assertEqual(len(self.app.study_details.get_children()), 72)
        self.assertIn("18 settings skipped", self.app.study_note["text"])
        self.app._clear_evaluation()
        self.assertEqual(len(self.app.study_details.get_children()), 0)

    def test_preview_resizing_keeps_status_visible(self):
        self.root.deiconify()
        self.root.geometry("850x650")
        self.root.update()

        self.app._show(
            "cover",
            np.zeros((512, 512, 3), np.uint8),
        )

        self.app._show(
            "extracted",
            np.zeros((32, 32), np.uint8),
        )

        for _ in range(12):
            self.root.update()
            time.sleep(0.01)

        for name in (
            "cover",
            "extracted",
        ):
            preview = self.app.previews[name]

            self.assertLessEqual(
                preview.photo.width(),
                preview.canvas.winfo_width(),
            )

            self.assertLessEqual(
                preview.photo.height(),
                preview.canvas.winfo_height(),
            )

        footer_bottom = (
            self.app.status_label.winfo_rooty()
            + self.app.status_label.winfo_height()
        )

        self.assertLessEqual(
            footer_bottom,
            self.root.winfo_rooty()
            + self.root.winfo_height(),
        )

        self.app.sidebar_canvas.yview_moveto(1.0)
        self.root.update()
        last_action = self.app.buttons["save_mark"]
        self.assertLessEqual(
            last_action.winfo_rooty() + last_action.winfo_height(),
            self.app.progress.winfo_rooty(),
        )

    def test_cancellation_and_worker_error(self):
        with patch(
            "watermark_app.filedialog.askopenfilename",
            return_value="",
        ):
            self.app.load("cover")

        self.assertIsNone(
            self.app.images["cover"]
        )

        self.assertFalse(self.app.busy)

        with patch(
            "watermark_app.messagebox.showerror"
        ) as error:
            self.app._start(
                lambda: 1 / 0,
                lambda result: None,
                "Testing an error",
            )

            self.finish()
            error.assert_called_once()

        self.assertEqual(
            str(self.app.buttons["cover"]["state"]),
            "normal",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
