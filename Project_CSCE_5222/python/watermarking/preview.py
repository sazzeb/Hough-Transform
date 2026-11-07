"""Reusable image preview widget for the desktop app."""

import tkinter as tk

from PIL import Image, ImageTk

from .theme import PALETTE


class ImagePreview(tk.Frame):
    """Show an image at a readable size inside one card."""
    def __init__(
        self,
        parent,
        title,
        pixelated=False,
        placeholder="Choose an image to preview",
        description=None,
    ):
        """Build the card and its drawing area."""
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

        if description is not None:
            tk.Label(
                self, text=description,
                bg=PALETTE["surface"], fg=PALETTE["muted"],
                font=("Helvetica", 9), anchor="w",
                justify="left", wraplength=132,
            ).pack(fill="x", padx=10)

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
        """Keep the new image and redraw it."""
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
        """Wait briefly before redrawing during a resize."""
        if self.resize_job is not None:
            self.after_cancel(self.resize_job)

        self.resize_job = self.after(
            60,
            self._redraw,
        )

    def _redraw(self):
        """Fit the image in the available canvas space."""
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
        """Cancel a pending redraw and release the image."""
        if self.resize_job is not None:
            self.after_cancel(self.resize_job)

        self.canvas.delete("all")
        self.photo = None
        self.source = None

        super().destroy()
