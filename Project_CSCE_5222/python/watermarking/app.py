from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import tkinter as tk
import sys
from tkinter import filedialog, messagebox, ttk

from PIL import Image
import numpy as np

from .image_io import ImageStore
from .examples import ExampleGallery, load_example_images
from .engine import WatermarkEngine, WatermarkError
from .layout import AppLayout
from .preview import ImagePreview
from .theme import PALETTE


class WatermarkApp(AppLayout):
    def __init__(self, root: tk.Tk):
        self.root = root

        self.root.title("Wavelet Watermark Studio")
        self.root.geometry("1360x860")
        self.root.minsize(900, 680)
        self.root.configure(bg=PALETTE["background"])

        self.images = dict.fromkeys(
            (
                "cover",
                "watermark",
                "watermarked",
                "extracted",
                "prepared",
                "difference",
            )
        )

        self.previews = {}
        self.stage_previews = {}
        self.metric_values = {}
        self.buttons = {}
        self.example_gallery = ExampleGallery()
        self.current_example = None
        self.recent_watermarked_path = None

        self.busy = False
        self.executor = ThreadPoolExecutor(max_workers=1)

        self.strength = tk.StringVar(value="16")
        self.side = tk.StringVar(value="32")
        self.mode = tk.StringVar(value="Balanced")
        self.strength_percent = tk.StringVar(value="Strength: 33%  •  16/32")
        self.preview_only = False
        self.preview_cover = None
        self.recovery_verified = False
        self.recovery_state = "Not checked"
        self.preview_job = None
        self.pending_full_refresh = False
        self._syncing_strength = False

        self.status = tk.StringVar(
            value=(
                "Try the example or load a cover and watermark. "
                "Save as PNG; extraction reads its embedded header."
            )
        )

        self._build_interface()
        self.strength.trace_add("write", self._strength_text_changed)
        self._update_controls()

        self.root.protocol(
            "WM_DELETE_WINDOW",
            self.close,
        )

    def _update_controls(self):
        enabled = {
            "sample": True,
            "cover": True,
            "watermark": True,
            "watermarked": True,
            "embed": (
                self.images["cover"] is not None
                and self.images["watermark"] is not None
            ),
            "extract": (
                self.images["watermarked"] is not None
                and not self.preview_only
            ),
            "save_image": (
                self.images["watermarked"] is not None
                and not self.preview_only
            ),
            "save_mark": (
                self.images["extracted"] is not None
                and not self.preview_only
            ),
            "evaluate": (
                self.images["cover"] is not None
                and self.images["watermark"] is not None
            ),
        }

        for name, button in self.buttons.items():
            button.configure(
                state=(
                    "normal"
                    if enabled[name] and not self.busy
                    else "disabled"
                )
            )

        for control in (
            self.strength_box,
            self.side_box,
            self.strength_scale,
        ):
            control.configure(
                state=(
                    "disabled"
                    if self.busy
                    else "normal"
                )
            )
        self.mode_box.configure(
            state="disabled" if self.busy else "readonly"
        )

    def _show(self, name, array):
        self.previews[name].set_image(array)

    @staticmethod
    def _haar_details(image):
        values = image[:512, :512].astype(np.float64)
        if values.ndim == 3:
            values = np.sum(
                values * np.array([0.299, 0.587, 0.114]), axis=2
            )
        height = values.shape[0] // 2 * 2
        width = values.shape[1] // 2 * 2
        a = values[:height:2, :width:2]
        b = values[:height:2, 1:width:2]
        c = values[1:height:2, :width:2]
        d = values[1:height:2, 1:width:2]
        return (a - b + c - d) / 2, (a + b - c - d) / 2

    def _refresh_evidence(self):
        if not self.metric_values:
            return
        original = self.preview_cover if self.preview_only else self.images["cover"]
        stages = {
            "source": self.images["cover"],
            "input": self.images["watermark"],
            "gray": self.images["prepared"],
            "haar": None,
            "changed": None,
            "decoded": (
                None if self.preview_only and self.preview_cover is None
                else self.images["extracted"]
            ),
        }
        if original is not None:
            horizontal, vertical = self._haar_details(original)
            stages["haar"] = np.minimum(
                255, 2 * np.hypot(horizontal, vertical)
            ).astype(np.uint8)
            marked = self.images["watermarked"]
            if marked is not None and marked.shape == original.shape:
                changed_horizontal, changed_vertical = self._haar_details(marked)
                stages["changed"] = np.minimum(
                    255, 4 * np.hypot(
                        horizontal - changed_horizontal,
                        vertical - changed_vertical,
                    )
                ).astype(np.uint8)

        for name, image in stages.items():
            self.stage_previews[name].set_image(image)

        values = {
            "psnr": "Need both images",
            "ssim": "Need both images",
            "ber": "Need both marks",
            "ncc": "Need both marks",
        }
        marked = self.images["watermarked"]
        if original is None and marked is not None:
            values["psnr"] = "Reference unavailable"
            values["ssim"] = "Reference unavailable"
        if original is not None and marked is not None and original.shape == marked.shape:
            values["psnr"] = f"{WatermarkEngine.psnr(original, marked):.2f} dB"
            values["ssim"] = f"{WatermarkEngine.ssim(original, marked):.4f}"

        prepared = self.images["prepared"]
        recovered = (
            None if self.preview_only and self.preview_cover is None
            else self.images["extracted"]
        )
        if prepared is None and recovered is not None:
            values["ber"] = "Reference unavailable"
            values["ncc"] = "Reference unavailable"
        if prepared is not None and recovered is not None and prepared.shape == recovered.shape:
            values["ber"] = (
                f"{100 * WatermarkEngine.bit_error_rate(prepared, recovered):.3f}%"
            )
            correlation = WatermarkEngine.normalized_correlation(
                prepared, recovered
            )
            values["ncc"] = (
                f"{correlation:.5f}" if np.isfinite(correlation) else "Undefined"
            )
        for name, value in values.items():
            self.metric_values[name].configure(text=value)

    @staticmethod
    def _embed_and_extract(cover, watermark, strength, side, mode="balanced"):
        embedded = WatermarkEngine.embed(
            cover, watermark, strength, (side, side), mode=mode
        )
        extracted = WatermarkEngine.extract(embedded.image)
        return embedded, extracted

    @staticmethod
    def _difference(original, changed):
        difference = np.abs(
            original.astype(np.int16) - changed.astype(np.int16)
        )
        if difference.ndim == 3:
            difference = difference.max(axis=2)
        return np.minimum(255, 4 * difference).astype(np.uint8)

    @staticmethod
    def _recovery_state(recovered, prepared):
        if not recovered.verified:
            return "Checksum failed; approximate"
        if prepared is None:
            return "Verified payload CRC; reference unavailable"
        if np.array_equal(recovered.watermark, prepared):
            return "Verified exact"
        return "Verified, pixels differ"

    def _clear_evaluation(self):
        for table in (self.study_summary, self.study_details):
            table.delete(*table.get_children())
        self.study_note.configure(
            text="No study for this image pair yet."
        )

    def run_evaluation(self):
        cover = self.images["cover"]
        watermark = self.images["watermark"]
        if self.busy or cover is None or watermark is None:
            return

        def display(report):
            for row in report["summary"]:
                values = list(row)
                values[4] = f"{100 * values[4]:.1f}%"
                values[8:10] = [
                    f"{value:.4f}" if np.isfinite(value) else "N/A"
                    for value in values[8:10]
                ]
                self.study_summary.insert("", "end", values=values)
            for row in report["details"]:
                values = list(row)
                values[5:9] = [
                    f"{value:.4f}" if np.isfinite(value) else "N/A"
                    for value in values[5:9]
                ]
                self.study_details.insert("", "end", values=values)
            height, width = report["working_size"]
            self.study_note.configure(
                text=(f"Working cover: {width} × {height} px; "
                      f"{report['skipped']} settings skipped for capacity. "
                      "Exact rate = verified, pixel-identical prepared "
                      "watermarks / tested cases. Header, Incomplete and "
                      "Checksum count distinct failures. N/A means no recovered "
                      "pixels; mean BER/NCC use only recovered cases. "
                      "Cover PSNR and 8×8 block luminance SSIM "
                      "are measured before the listed change.")
            )
            self.status.set(
                f"Study complete: {len(report['details'])} tested cases; "
                f"{report['skipped']} settings skipped."
            )

        self._clear_evaluation()
        self._start(
            lambda: WatermarkEngine.evaluate_robustness(cover, watermark),
            display, "Running the robustness study…",
        )

    def _selected_mode(self):
        return self.mode.get().lower()

    def _strength_text_changed(self, *_args):
        if self._syncing_strength:
            return
        try:
            strength = int(self.strength.get())
        except ValueError:
            return
        if not 8 <= strength <= 32:
            return
        percentage = round(100 * (strength - 8) / 24)
        self._syncing_strength = True
        try:
            self.strength_scale.set(percentage)
            self.strength_percent.set(
                f"Strength: {percentage}%  •  {strength}/32"
            )
        finally:
            self._syncing_strength = False

    def _strength_drag(self, value):
        if self._syncing_strength:
            return
        percentage = int(round(float(value)))
        strength = 8 + round(24 * percentage / 100)
        self._syncing_strength = True
        try:
            self.strength.set(str(strength))
        finally:
            self._syncing_strength = False
        self.strength_percent.set(
            f"Strength: {percentage}%  •  {strength}/32"
        )
        if self.busy or self.images["cover"] is None or self.images["watermark"] is None:
            return
        self.preview_only = True
        self.preview_cover = None
        self._refresh_evidence()
        self._update_controls()
        if self.preview_job is not None:
            self.root.after_cancel(self.preview_job)
        self.preview_job = self.root.after(150, self._show_strength_preview)

    def _show_strength_preview(self):
        self.preview_job = None
        if self.busy:
            self.preview_job = self.root.after(150, self._show_strength_preview)
            return
        try:
            side = int(self.side.get())
            strength = int(self.strength.get())
            cover = self.images["cover"]
            crop = cover[:min(640, cover.shape[0]), :min(640, cover.shape[1])].copy()
            if side * side > WatermarkEngine.capacity_bytes(
                crop, self._selected_mode()
            ):
                self.status.set("This setting needs a larger cover image.")
                return
        except (ValueError, TypeError) as error:
            self.status.set(f"Preview unavailable: {error}")
            return

        def completed(result):
            embedded, extracted = result
            self.preview_only = True
            self.preview_cover = crop
            self.recovery_verified = extracted.verified
            self.recovery_state = "Live crop preview"
            self.images["watermarked"] = embedded.image
            self.images["extracted"] = extracted.watermark
            self.images["prepared"] = embedded.prepared_watermark
            self.images["difference"] = self._difference(crop, embedded.image)
            for name in ("watermarked", "extracted", "prepared", "difference"):
                self._show(name, self.images[name])
            self._refresh_evidence()
            self.status.set(
                f"Live {self.strength_scale.get()}% crop preview · "
                f"{embedded.psnr:.2f} dB PSNR. Release to create the full image."
            )

        watermark = self.images["watermark"]
        mode = self._selected_mode()
        self._start(
            lambda: WatermarkApp._embed_and_extract(
                crop, watermark, strength, side, mode,
            ), completed, "Updating the live preview…",
        )

    def _strength_release(self, _event):
        if self.preview_job is not None:
            self.root.after_cancel(self.preview_job)
            self.preview_job = None
        if self.images["watermark"] is not None:
            try:
                side = int(self.side.get())
                self.images["prepared"] = WatermarkEngine.prepare_watermark(
                    self.images["watermark"], (side, side)
                )
                self._show("prepared", self.images["prepared"])
                self._refresh_evidence()
            except ValueError:
                pass
        if self.images["cover"] is None or self.images["watermark"] is None:
            return
        self.pending_full_refresh = True
        if not self.busy:
            self._refresh_full_from_slider()

    def _refresh_full_from_slider(self):
        self.pending_full_refresh = False
        self.embed()

    def _mode_changed(self, _event):
        if self.images["cover"] is not None and self.images["watermark"] is not None:
            self._strength_release(None)

    def _display_embedding(self, embedded, extracted):
        self.preview_only = False
        self.preview_cover = None
        self.recovery_verified = extracted.verified
        self.recovery_state = self._recovery_state(
            extracted, embedded.prepared_watermark
        )
        self.images["watermarked"] = embedded.image
        self.images["extracted"] = extracted.watermark
        self.images["prepared"] = embedded.prepared_watermark
        self.images["difference"] = self._difference(
            self.images["cover"], embedded.image
        )
        self._show("watermarked", embedded.image)
        self._show("extracted", extracted.watermark)
        self._show("prepared", embedded.prepared_watermark)
        self._show("difference", self.images["difference"])
        self._refresh_evidence()
        self.status.set(
            f"Embedded and extracted a "
            f"{extracted.watermark.shape[1]} × "
            f"{extracted.watermark.shape[0]} grayscale watermark. "
            f"Mode: {self.mode.get()}; "
            f"strength: {embedded.strength} ({self.strength_scale.get()}%); "
            f"PSNR: {embedded.psnr:.2f} dB. "
            f"Recovery: {self.recovery_state}. Save the watermarked PNG "
            "to keep it; JPEG output is not supported because it is lossy."
        )

    def try_sample(self):
        if self.busy:
            return

        mode = self._selected_mode()
        example = self.example_gallery.next_example()

        def operation():
            cover, watermark = load_example_images(example)
            embedded, extracted = WatermarkApp._embed_and_extract(
                cover, watermark, 16, 32, mode
            )
            return cover, watermark, embedded, extracted

        def completed(result):
            cover, watermark, embedded, extracted = result
            self._clear_evaluation()
            self.strength.set("16")
            self.strength_scale.set(33)
            self.side.set("32")
            self.images["cover"] = cover
            self.images["watermark"] = watermark
            self._show("cover", cover)
            self._show("watermark", watermark)
            self._display_embedding(embedded, extracted)
            self.current_example = example
            self.status.set(f"Example: {example['title']}. {self.status.get()}")

        self._start(
            operation, completed, "Loading and testing the example…"
        )

    def _start(
        self,
        operation,
        on_success,
        message,
    ):
        if self.busy:
            return

        self.busy = True
        self.status.set(message)

        self._update_controls()
        self.progress.start(12)

        future = self.executor.submit(operation)

        def poll():
            if not future.done():
                self.root.after(40, poll)
                return

            try:
                on_success(future.result())

            except Exception as error:
                # The interface is the final boundary for worker errors.
                self.status.set(
                    f"Operation failed: {error}"
                )

                messagebox.showerror(
                    "Operation failed",
                    str(error),
                    parent=self.root,
                )

            finally:
                self.busy = False
                self.progress.stop()
                self._update_controls()
                if self.pending_full_refresh:
                    self.root.after(0, self._refresh_full_from_slider)

        self.root.after(40, poll)

    def load(self, name):
        if self.busy:
            return

        types = (
            [("PNG images", "*.png")]
            if name == "watermarked"
            else [
                (
                    "Supported images",
                    "*.png *.jpg *.jpeg *.bmp",
                ),
                ("All files", "*.*"),
            ]
        )

        picker_options = dict(
            title=("Open saved watermarked PNG" if name == "watermarked"
                   else f"Load {name}"),
            filetypes=types,
        )
        if name == "watermarked" and self.recent_watermarked_path:
            recent = Path(self.recent_watermarked_path)
            if recent.is_file():
                picker_options["initialdir"] = str(recent.parent)
                picker_options["initialfile"] = recent.name

        path = self._choose_file(
            filedialog.askopenfilename,
            **picker_options,
        )

        if not path:
            return

        def operation():
            with Image.open(path) as source:
                source_size = source.size
            image = ImageStore.read(
                path, watermarked=name == "watermarked"
            )
            recovered = None
            if name == "watermarked":
                try:
                    recovered = WatermarkEngine.extract(image)
                except WatermarkError as error:
                    raise WatermarkError(
                        "This PNG has no recoverable watermark. Select "
                        "the unchanged file created by Save watermarked "
                        "PNG, not the original photo or recovered "
                        f"watermark. Details: {error}"
                    ) from error
            return image, recovered, source_size

        def completed(result):
            array, recovered, source_size = result
            self._clear_evaluation()
            self.preview_only = False
            self.preview_cover = None
            self.recovery_verified = recovered.verified if recovered is not None else False
            self.recovery_state = (
                self._recovery_state(recovered, None)
                if recovered is not None else "Not checked"
            )
            if name == "watermarked":
                for input_name in ("cover", "watermark"):
                    self.images[input_name] = None
                    self._show(input_name, None)
            self.images[name] = array
            self._show(name, array)

            invalidated = (
                ("watermarked", "extracted", "prepared", "difference")
                if name != "watermarked"
                else ("extracted", "prepared", "difference")
            )

            for output in invalidated:
                self.images[output] = None
                self._show(output, None)

            if recovered is not None:
                self.recent_watermarked_path = path
                self.images["extracted"] = recovered.watermark
                self._show("extracted", recovered.watermark)
            elif self.images["watermark"] is not None:
                try:
                    side = int(self.side.get())
                    self.images["prepared"] = WatermarkEngine.prepare_watermark(
                        self.images["watermark"], (side, side)
                    )
                    self._show("prepared", self.images["prepared"])
                except ValueError:
                    pass

            details = (
                f"Loaded {Path(path).name}: "
                f"{array.shape[1]} × {array.shape[0]}."
            )

            if source_size != (array.shape[1], array.shape[0]):
                details += (
                    f" Resized from {source_size[0]} × "
                    f"{source_size[1]} for safe processing; "
                    "original file unchanged."
                )

            if name == "cover":
                details += (
                    " Payload capacity: "
                    f"{WatermarkEngine.capacity_bytes(array, self._selected_mode())} bytes."
                )

            if recovered is not None:
                recovery_message = (
                    "Payload checksum verified; original reference unavailable"
                    if recovered.verified else
                    "Approximate watermark recovered; checksum failed"
                )
                details += (
                    f" {recovery_message}: "
                    f"{recovered.watermark.shape[1]} × "
                    f"{recovered.watermark.shape[0]}, "
                    f"strength {recovered.strength}."
                )

            self.status.set(details)
            self._refresh_evidence()

        self._start(
            operation,
            completed,
            "Loading image…",
        )

    def embed(self):
        if (
            self.busy
            or self.images["cover"] is None
            or self.images["watermark"] is None
        ):
            return

        try:
            strength = int(self.strength.get())
            side = int(self.side.get())
            mode = self._selected_mode()

        except ValueError as error:
            messagebox.showerror(
                "Invalid settings",
                str(error),
                parent=self.root,
            )

            return

        def completed(result):
            self._display_embedding(*result)

        cover = self.images["cover"]
        watermark = self.images["watermark"]
        self._start(
            lambda: WatermarkApp._embed_and_extract(
                cover,
                watermark,
                strength,
                side,
                mode,
            ),
            completed,
            "Embedding and checking recovery…",
        )

    def extract(self):
        if (
            self.busy
            or self.images["watermarked"] is None
            or self.preview_only
        ):
            return

        def completed(result):
            self.images["extracted"] = result.watermark
            self.recovery_verified = result.verified
            self.recovery_state = self._recovery_state(
                result, self.images["prepared"]
            )

            self._show(
                "extracted",
                result.watermark,
            )
            self._refresh_evidence()

            recovery_message = (
                f"Extraction: {self.recovery_state}."
                if result.verified else
                "Approximate recovery: payload checksum failed."
            )
            self.status.set(
                f"{recovery_message} "
                f"Stored strength: {result.strength}. "
                f"Watermark: {result.watermark.shape[1]} "
                f"× {result.watermark.shape[0]}."
            )

        watermarked = self.images["watermarked"]
        self._start(
            lambda: WatermarkEngine.extract(watermarked),
            completed,
            "Extracting and verifying watermark…",
        )

    def save(self, name):
        if (
            self.busy
            or self.images[name] is None
            or self.preview_only
        ):
            return

        path = self._choose_file(
            filedialog.asksaveasfilename,
            title=f"Save {name}",
            initialfile=f"{name}.png",
            defaultextension=".png",
            filetypes=[("PNG images", "*.png")],
        )

        if path:
            image = self.images[name]
            def operation():
                saved = ImageStore.save_png(path, image)
                recovered = None

                if name == "watermarked":
                    reopened = ImageStore.read(
                        saved, watermarked=True
                    )
                    recovered = WatermarkEngine.extract(reopened)

                return saved, recovered

            def completed(result):
                saved, recovered = result

                if recovered is not None:
                    self.recent_watermarked_path = saved
                    self.images["extracted"] = recovered.watermark
                    self.recovery_verified = recovered.verified
                    self.recovery_state = self._recovery_state(
                        recovered, self.images["prepared"]
                    )
                    self._show("extracted", recovered.watermark)
                    if recovered.verified:
                        self.status.set(
                            f"Saved {saved}. Reopened the PNG and "
                            f"recovered its watermark: {self.recovery_state}."
                        )
                    else:
                        self.status.set(
                            f"Saved {saved}. Recovery remains approximate; "
                            "the payload checksum failed."
                        )
                else:
                    if self.recovery_verified:
                        self.status.set(f"Verified and saved: {saved}")
                    else:
                        self.status.set(
                            f"Saved approximate watermark: {saved}. "
                            "The payload checksum failed."
                        )
                self._refresh_evidence()

            self._start(
                operation,
                completed,
                "Saving and verifying PNG…",
            )

    def _choose_file(self, dialog, **options):
        if sys.platform == "darwin":
            # An owned macOS picker is a sheet and cannot be moved
            # independently. Use a standalone native dialog instead.
            self.root.lower()
            try:
                return dialog(**options)
            finally:
                self.root.lift()

        return dialog(parent=self.root, **options)

    def close(self):
        if self.busy:
            messagebox.showinfo(
                "Operation in progress",
                "Close the window after the current operation finishes.",
                parent=self.root,
            )

            return

        if self.preview_job is not None:
            self.root.after_cancel(self.preview_job)
            self.preview_job = None

        self.executor.shutdown(
            wait=False,
            cancel_futures=True,
        )

        self.root.destroy()


def main():
    root = tk.Tk()
    WatermarkApp(root)
    root.mainloop()


if __name__ == "__main__":
    main()
