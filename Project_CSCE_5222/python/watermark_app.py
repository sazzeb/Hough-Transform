from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import tkinter as tk
import sys
from tkinter import filedialog, messagebox, ttk

from PIL import Image, ImageTk

from image_io import ImageStore
from sample_data import load_sample_images
from watermark_core import WatermarkEngine


PALETTE = {
    "background": "#FFFFFF",
    "surface": "#FFFFFF",
    "header": "#266435",
    "text": "#000000",
    "muted": "#333333",
    "border": "#266435",
    "accent": "#266435",
    "accent_hover": "#1D4F2A",
    "success": "#266435",
}


class ImagePreview(tk.Frame):
    def __init__(
        self,
        parent,
        title,
        pixelated=False,
        placeholder="Choose an image to preview",
    ):
        super().__init__(
            parent,
            bg=PALETTE["surface"],
            highlightbackground=PALETTE["border"],
            highlightthickness=1,
        )

        self.source = None
        self.photo = None
        self.resize_job = None
        self.pixelated = pixelated
        self.placeholder = placeholder

        heading = tk.Frame(self, bg=PALETTE["surface"])
        heading.pack(fill="x", padx=14, pady=(12, 8))

        tk.Label(
            heading,
            text=title,
            bg=PALETTE["surface"],
            fg=PALETTE["text"],
            font=("Helvetica", 12, "bold"),
            anchor="w",
        ).pack(side="left")

        self.details = tk.Label(
            self,
            text="No image loaded",
            bg=PALETTE["surface"],
            fg=PALETTE["muted"],
            font=("Helvetica", 10),
            anchor="w",
        )
        self.details.pack(side="bottom", fill="x", padx=14, pady=(7, 11))

        self.canvas = tk.Canvas(
            self,
            width=180,
            height=120,
            bg=PALETTE["background"],
            highlightthickness=0,
        )

        self.canvas.pack(
            fill="both",
            expand=True,
            padx=14,
        )

        self.canvas.bind(
            "<Configure>",
            self._schedule_redraw,
        )

    def set_image(self, array):
        self.source = (
            None
            if array is None
            else Image.fromarray(array)
        )

        self.details.configure(
            text=(
                "No image loaded"
                if self.source is None
                else f"{self.source.width} × {self.source.height} px"
            )
        )

        self._redraw()

    def _schedule_redraw(self, _event):
        if self.resize_job is not None:
            self.after_cancel(self.resize_job)

        self.resize_job = self.after(
            60,
            self._redraw,
        )

    def _redraw(self):
        if self.resize_job is not None:
            self.after_cancel(self.resize_job)
            self.resize_job = None

        width = max(1, self.canvas.winfo_width())
        height = max(1, self.canvas.winfo_height())

        self.canvas.delete("all")

        if self.source is None:
            self.photo = None

            self.canvas.create_text(
                width / 2,
                height / 2,
                text=self.placeholder,
                fill=PALETTE["muted"],
                font=("Helvetica", 11),
                width=max(100, width - 30),
                justify="center",
            )

            return

        ratio = min(
            max(1, width - 12) / self.source.width,
            max(1, height - 12) / self.source.height,
        )

        size = (
            max(1, int(self.source.width * ratio)),
            max(1, int(self.source.height * ratio)),
        )

        method = (
            Image.Resampling.NEAREST
            if self.pixelated
            else Image.Resampling.LANCZOS
        )

        picture = self.source.resize(
            size,
            method,
        )

        self.photo = ImageTk.PhotoImage(
            picture,
            master=self.canvas,
        )

        self.canvas.create_image(
            width / 2,
            height / 2,
            image=self.photo,
        )

    def destroy(self):
        if self.resize_job is not None:
            self.after_cancel(self.resize_job)

        super().destroy()


class WatermarkApp:
    def __init__(self, root: tk.Tk):
        self.root = root

        self.root.title("Wavelet Watermark Studio")
        self.root.geometry("1180x790")
        self.root.minsize(900, 680)
        self.root.configure(bg=PALETTE["background"])

        self.images = dict.fromkeys(
            (
                "cover",
                "watermark",
                "watermarked",
                "extracted",
            )
        )

        self.previews = {}
        self.buttons = {}

        self.busy = False
        self.executor = ThreadPoolExecutor(max_workers=1)

        self.strength = tk.StringVar(value="16")
        self.side = tk.StringVar(value="32")

        self.status = tk.StringVar(
            value=(
                "Try the example or load a cover and watermark. "
                "Save as PNG; extraction reads its embedded header."
            )
        )

        self._build_interface()
        self._update_controls()

        self.root.protocol(
            "WM_DELETE_WINDOW",
            self.close,
        )

    def _build_interface(self):
        self._configure_style()

        header = tk.Frame(self.root, bg=PALETTE["header"])
        header.pack(fill="x")

        tk.Label(
            header,
            text="IMAGE LAB  /  WAVELET WATERMARKING",
            bg=PALETTE["header"],
            fg=PALETTE["surface"],
            font=("Helvetica", 10, "bold"),
            anchor="w",
        ).pack(fill="x", padx=24, pady=(16, 2))

        tk.Label(
            header,
            text="Hide an image. Recover it. See every step.",
            bg=PALETTE["header"],
            fg=PALETTE["surface"],
            font=("Helvetica", 17, "bold"),
            anchor="w",
        ).pack(fill="x", padx=24, pady=(0, 18))

        workspace = tk.Frame(self.root, bg=PALETTE["background"])
        workspace.pack(fill="both", expand=True, padx=16, pady=14)
        workspace.grid_columnconfigure(1, weight=1)
        workspace.grid_rowconfigure(0, weight=1)

        sidebar = tk.Frame(
            workspace,
            bg=PALETTE["surface"],
            highlightbackground=PALETTE["border"],
            highlightthickness=1,
            width=254,
        )
        sidebar.grid(row=0, column=0, sticky="ns", padx=(0, 12))
        sidebar.grid_propagate(False)

        controls = tk.Frame(sidebar, bg=PALETTE["surface"])
        controls.pack(fill="both", expand=True, padx=14, pady=12)

        self._section(controls, "QUICK START")
        self._button(
            controls, "sample", "Try an example", self.try_sample,
            primary=True,
        )

        self._section(controls, "01  INPUT IMAGES")
        self._button(
            controls, "cover", "Choose original image",
            lambda: self.load("cover"),
        )
        self._button(
            controls, "watermark", "Choose image to hide",
            lambda: self.load("watermark"),
        )
        self._button(
            controls, "watermarked", "Choose watermarked PNG",
            lambda: self.load("watermarked"),
        )

        self._section(controls, "02  EMBEDDING SETTINGS")
        self.strength_box = self._setting(
            controls, "Strength  ·  8–32", self.strength, 8, 32
        )
        self.side_box = self._setting(
            controls, "Watermark side  ·  8–64", self.side, 8, 64
        )

        self._section(controls, "03  PROCESS")
        self._button(
            controls, "embed", "Create watermarked image", self.embed,
            primary=True,
        )
        self._button(
            controls, "extract", "Recover watermark", self.extract,
        )

        self._section(controls, "04  SAVE RESULTS")
        self._button(
            controls, "save_image", "Save watermarked PNG",
            lambda: self.save("watermarked"),
        )
        self._button(
            controls, "save_mark", "Save recovered watermark",
            lambda: self.save("extracted"),
        )

        previews = tk.Frame(workspace, bg=PALETTE["background"])
        previews.grid(row=0, column=1, sticky="nsew")

        captions = (
            ("cover", "Original image", "Choose an original image"),
            ("watermark", "Image to hide", "Choose an image to hide"),
            ("watermarked", "Watermarked image", "Embed to see the result"),
            ("extracted", "Recovered watermark", "Recover a watermark"),
        )

        for index, (name, caption, placeholder) in enumerate(captions):
            panel = ImagePreview(
                previews,
                caption,
                pixelated=name in {"watermark", "extracted"},
                placeholder=placeholder,
            )
            panel.grid(
                row=index // 2,
                column=index % 2,
                padx=5,
                pady=5,
                sticky="nsew",
            )
            self.previews[name] = panel

        for index in range(2):
            previews.grid_rowconfigure(index, weight=1)
            previews.grid_columnconfigure(index, weight=1)

        footer = tk.Frame(self.root, bg=PALETTE["surface"])
        footer.pack(fill="x", side="bottom")

        self.progress = ttk.Progressbar(
            footer, mode="indeterminate", style="Work.Horizontal.TProgressbar"
        )
        self.progress.pack(fill="x")

        self.status_label = tk.Label(
            footer,
            textvariable=self.status,
            bg=PALETTE["surface"],
            fg=PALETTE["text"],
            font=("Helvetica", 10),
            anchor="w",
            justify="left",
            wraplength=1000,
        )
        self.status_label.pack(fill="x", padx=20, pady=(9, 11))
        footer.bind(
            "<Configure>",
            lambda event: self.status_label.configure(
                wraplength=max(200, event.width - 40)
            ),
        )

    @staticmethod
    def _configure_style():
        style = ttk.Style()
        style.theme_use("clam")
        style.configure(
            "Primary.TButton",
            background=PALETTE["accent"],
            foreground=PALETTE["surface"],
            borderwidth=0,
            padding=(12, 6),
            font=("Helvetica", 10, "bold"),
            anchor="w",
        )
        style.map(
            "Primary.TButton",
            background=[
                ("disabled", PALETTE["border"]),
                ("active", PALETTE["accent_hover"]),
            ],
            foreground=[("disabled", PALETTE["muted"])],
        )
        style.configure(
            "Secondary.TButton",
            background=PALETTE["background"],
            foreground=PALETTE["text"],
            bordercolor=PALETTE["border"],
            borderwidth=1,
            padding=(11, 5),
            font=("Helvetica", 10),
            anchor="w",
        )
        style.map(
            "Secondary.TButton",
            background=[
                ("disabled", PALETTE["surface"]),
                ("active", "#E8F1E9"),
            ],
            foreground=[("disabled", PALETTE["muted"])],
        )
        style.configure(
            "Work.Horizontal.TProgressbar",
            background=PALETTE["accent"],
            troughcolor=PALETTE["border"],
            thickness=3,
            borderwidth=0,
        )

    @staticmethod
    def _section(parent, title):
        tk.Label(
            parent,
            text=title,
            bg=PALETTE["surface"],
            fg=PALETTE["muted"],
            font=("Helvetica", 9, "bold"),
            anchor="w",
        ).pack(fill="x", pady=(12, 5))

    def _button(self, parent, name, caption, callback, primary=False):
        button = ttk.Button(
            parent,
            text=caption,
            command=callback,
            style="Primary.TButton" if primary else "Secondary.TButton",
        )
        button.pack(fill="x", pady=2)
        self.buttons[name] = button

    @staticmethod
    def _setting(parent, caption, variable, minimum, maximum):
        row = tk.Frame(parent, bg=PALETTE["surface"])
        row.pack(fill="x", pady=2)

        tk.Label(
            row,
            text=caption,
            bg=PALETTE["surface"],
            fg=PALETTE["text"],
            font=("Helvetica", 10),
            anchor="w",
        ).pack(side="left", fill="x", expand=True)

        control = ttk.Spinbox(
            row,
            from_=minimum,
            to=maximum,
            textvariable=variable,
            width=5,
            justify="center",
        )
        control.pack(side="right")
        return control

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
            ),
            "save_image": (
                self.images["watermarked"] is not None
            ),
            "save_mark": (
                self.images["extracted"] is not None
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
        ):
            control.configure(
                state=(
                    "disabled"
                    if self.busy
                    else "normal"
                )
            )

    def _show(self, name, array):
        self.previews[name].set_image(array)

    @staticmethod
    def _embed_and_extract(cover, watermark, strength, side):
        embedded = WatermarkEngine.embed(
            cover, watermark, strength, (side, side)
        )
        extracted = WatermarkEngine.extract(embedded.image)
        return embedded, extracted

    def _display_embedding(self, embedded, extracted):
        self.images["watermarked"] = embedded.image
        self.images["extracted"] = extracted.watermark
        self._show("watermarked", embedded.image)
        self._show("extracted", extracted.watermark)
        self.status.set(
            f"Embedded and extracted a "
            f"{extracted.watermark.shape[1]} × "
            f"{extracted.watermark.shape[0]} grayscale watermark. "
            f"across all image channels. Strength: {embedded.strength}; "
            f"PSNR: {embedded.psnr:.2f} dB. "
            "Exact recovery passed. Save the watermarked PNG "
            "to keep it; JPEG output is not supported because it is lossy."
        )

    def try_sample(self):
        if self.busy:
            return

        def operation():
            cover, watermark = load_sample_images()
            embedded, extracted = self._embed_and_extract(
                cover, watermark, 16, 32
            )
            return cover, watermark, embedded, extracted

        def completed(result):
            cover, watermark, embedded, extracted = result
            self.strength.set("16")
            self.side.set("32")
            self.images["cover"] = cover
            self.images["watermark"] = watermark
            self._show("cover", cover)
            self._show("watermark", watermark)
            self._display_embedding(embedded, extracted)

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

        path = self._choose_file(
            filedialog.askopenfilename,
            title=f"Load {name}",
            filetypes=types,
        )

        if not path:
            return

        def operation():
            image = ImageStore.read(
                path, watermarked=name == "watermarked"
            )
            recovered = (
                WatermarkEngine.extract(image)
                if name == "watermarked"
                else None
            )
            return image, recovered

        def completed(result):
            array, recovered = result
            self.images[name] = array
            self._show(name, array)

            invalidated = (
                ("watermarked", "extracted")
                if name != "watermarked"
                else ("extracted",)
            )

            for output in invalidated:
                self.images[output] = None
                self._show(output, None)

            if recovered is not None:
                self.images["extracted"] = recovered.watermark
                self._show("extracted", recovered.watermark)

            details = (
                f"Loaded {Path(path).name}: "
                f"{array.shape[1]} × {array.shape[0]}."
            )

            if name == "cover":
                details += (
                    " Payload capacity: "
                    f"{WatermarkEngine.capacity_bytes(array)} bytes."
                )

            if recovered is not None:
                details += (
                    " Watermark extracted and checked: "
                    f"{recovered.watermark.shape[1]} × "
                    f"{recovered.watermark.shape[0]}, "
                    f"strength {recovered.strength}."
                )

            self.status.set(details)

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

        except ValueError as error:
            messagebox.showerror(
                "Invalid settings",
                str(error),
                parent=self.root,
            )

            return

        def completed(result):
            self._display_embedding(*result)

        self._start(
            lambda: self._embed_and_extract(
                self.images["cover"],
                self.images["watermark"],
                strength,
                side,
            ),
            completed,
            "Embedding and checking recovery…",
        )

    def extract(self):
        if (
            self.busy
            or self.images["watermarked"] is None
        ):
            return

        def completed(result):
            self.images["extracted"] = result.watermark

            self._show(
                "extracted",
                result.watermark,
            )

            self.status.set(
                "Extraction passed both checksums. "
                f"Stored strength: {result.strength}. "
                f"Watermark: {result.watermark.shape[1]} "
                f"× {result.watermark.shape[0]}."
            )

        self._start(
            lambda: WatermarkEngine.extract(
                self.images["watermarked"]
            ),
            completed,
            "Extracting and verifying watermark…",
        )

    def save(self, name):
        if (
            self.busy
            or self.images[name] is None
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
            def operation():
                saved = ImageStore.save_png(path, self.images[name])
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
                    self.images["extracted"] = recovered.watermark
                    self._show("extracted", recovered.watermark)
                    self.status.set(
                        f"Saved {saved}. Reopened the PNG and "
                        "recovered its watermark."
                    )
                else:
                    self.status.set(f"Verified and saved: {saved}")

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
