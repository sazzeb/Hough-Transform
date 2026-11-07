"""Layout and widget construction for the watermark desktop app."""

import tkinter as tk
from tkinter import ttk

from .preview import ImagePreview
from .theme import PALETTE


class AppLayout:
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

        self.sidebar_canvas = tk.Canvas(
            sidebar, bg=PALETTE["surface"],
            highlightthickness=0, borderwidth=0,
        )
        sidebar_scroll = ttk.Scrollbar(
            sidebar, orient="vertical", command=self.sidebar_canvas.yview
        )
        self.sidebar_canvas.configure(yscrollcommand=sidebar_scroll.set)
        sidebar_scroll.pack(side="right", fill="y")
        self.sidebar_canvas.pack(side="left", fill="both", expand=True)
        controls = tk.Frame(self.sidebar_canvas, bg=PALETTE["surface"])
        self.sidebar_window = self.sidebar_canvas.create_window(
            (13, 12), window=controls, anchor="nw"
        )
        self.sidebar_canvas.bind(
            "<Configure>",
            lambda event: self.sidebar_canvas.itemconfigure(
                self.sidebar_window, width=max(180, event.width - 26)
            ),
        )
        controls.bind(
            "<Configure>",
            lambda _event: self.sidebar_canvas.configure(
                scrollregion=self.sidebar_canvas.bbox("all")
            ),
        )

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
            controls, "watermarked", "Open saved watermarked PNG",
            lambda: self.load("watermarked"),
        )
        tk.Label(
            controls,
            text=(
                "For the current result, use Recover watermark below. "
                "Here, select only the PNG made by Save watermarked PNG."
            ),
            bg=PALETTE["surface"], fg=PALETTE["muted"],
            wraplength=250, justify="left", anchor="w",
        ).pack(fill="x", pady=(2, 7))

        self._section(controls, "02  EMBEDDING SETTINGS")
        self.strength_box = self._setting(
            controls, "Strength  ·  8–32", self.strength, 8, 32
        )
        self.strength_scale = tk.Scale(
            controls, from_=0, to=100, orient="horizontal",
            showvalue=False, resolution=1,
            command=self._strength_drag,
            bg=PALETTE["surface"], fg=PALETTE["text"],
            troughcolor=PALETTE["accent"],
            highlightthickness=0,
        )
        self.strength_scale.pack(fill="x")
        self.strength_scale.set(33)
        self.strength_scale.bind("<ButtonRelease-1>", self._strength_release)
        tk.Label(
            controls, textvariable=self.strength_percent,
            bg=PALETTE["surface"], fg=PALETTE["text"],
            anchor="w",
        ).pack(fill="x")
        self.side_box = self._setting(
            controls, "Watermark side  ·  8–64", self.side, 8, 64
        )
        self.mode_box = ttk.Combobox(
            controls, textvariable=self.mode,
            values=("Balanced", "Durable", "Classic"),
            state="readonly",
        )
        self.mode_box.pack(fill="x", pady=(4, 2))
        self.mode_box.bind("<<ComboboxSelected>>", self._mode_changed)
        self.strength_box.bind("<FocusOut>", self._strength_release)
        self.strength_box.bind("<Return>", self._strength_release)
        self.side_box.bind("<FocusOut>", self._strength_release)
        self.side_box.bind("<Return>", self._strength_release)
        tk.Label(
            controls,
            text=("0–100% controls strength 8–32; it is not the percentage "
                  "of pixels changed. Durable adds redundancy against "
                  "limited pixel damage. "
                  "Keep the original PNG; JPEG, cropping and resizing may prevent recovery."),
            bg=PALETTE["surface"], fg=PALETTE["text"],
            wraplength=218, justify="left", anchor="w",
        ).pack(fill="x", pady=(3, 1))

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

        self._section(controls, "05  EVALUATE")
        self._button(
            controls, "evaluate", "Run robustness study",
            self.run_evaluation,
        )
        tk.Label(
            controls,
            text="Uses the selected image pair at up to 512 pixels per side.",
            bg=PALETTE["surface"], fg=PALETTE["muted"],
            wraplength=218, justify="left", anchor="w",
        ).pack(fill="x", pady=(3, 4))

        evidence = tk.Frame(workspace, bg=PALETTE["background"])
        evidence.grid(row=0, column=1, sticky="nsew")
        evidence.grid_rowconfigure(0, weight=1)
        evidence.grid_columnconfigure(0, weight=1)
        evidence_canvas = tk.Canvas(
            evidence, bg=PALETTE["background"], highlightthickness=0
        )
        evidence_scroll = ttk.Scrollbar(
            evidence, orient="vertical", command=evidence_canvas.yview
        )
        evidence_canvas.configure(yscrollcommand=evidence_scroll.set)
        evidence_canvas.grid(row=0, column=0, sticky="nsew")
        evidence_scroll.grid(row=0, column=1, sticky="ns")
        content = tk.Frame(evidence_canvas, bg=PALETTE["background"])
        content_window = evidence_canvas.create_window(
            (0, 0), window=content, anchor="nw"
        )
        content.bind(
            "<Configure>",
            lambda _event: evidence_canvas.configure(
                scrollregion=evidence_canvas.bbox("all")
            ),
        )
        evidence_canvas.bind(
            "<Configure>",
            lambda event: evidence_canvas.itemconfigure(
                content_window, width=event.width
            ),
        )

        self._section(content, "01  IMAGE → PREPARATION → HAAR DETAILS → RECOVERY")
        stage_grid = tk.Frame(content, bg=PALETTE["background"])
        stage_grid.pack(fill="x", pady=(3, 9))
        stages = (
            ("source", "1  Original", "Cover image"),
            ("input", "2  Image to hide", "Selected watermark"),
            ("gray", "3  Prepared", "Grayscale + fit"),
            ("haar", "4  Haar details", "First 512 × 512 · magnitude ×2 for display"),
            ("changed", "5  Embedded detail", "First 512 × 512 · change ×4 for display"),
            ("decoded", "6  Decoded", "Recovered bytes"),
        )
        for index, (name, caption, placeholder) in enumerate(stages):
            panel = ImagePreview(
                stage_grid, caption,
                pixelated=name in {"gray", "decoded"},
                placeholder=placeholder,
                description=placeholder,
            )
            panel.configure(height=340)
            panel.canvas.configure(height=250)
            panel.grid(
                row=index // 2, column=index % 2,
                sticky="nsew", padx=5, pady=5,
            )
            panel.pack_propagate(False)
            self.stage_previews[name] = panel
        for column in range(2):
            stage_grid.grid_columnconfigure(
                column, weight=1, uniform="stage"
            )

        tk.Label(
            content,
            text=("Haar maps show the first 512 × 512 pixels. The ×4 "
                  "coefficient map is display-only; scores use true pixels."),
            bg=PALETTE["background"], fg=PALETTE["muted"],
            anchor="w", justify="left", wraplength=760,
        ).pack(fill="x", pady=(0, 7))

        self._section(content, "QUALITY AND RECOVERY SCORES")
        measures = tk.Frame(content, bg=PALETTE["background"])
        measures.pack(fill="x", pady=(0, 12))
        metric_specs = (
            ("psnr", "COVER · PSNR", "Original → watermarked · 10log10(255²/MSE)"),
            ("ssim", "COVER · SSIM", "Original → watermarked · 8×8 block luminance variant"),
            ("ber", "RECOVERY · BER", "Prepared grayscale → recovered · wrong bits / all bits"),
            ("ncc", "RECOVERY · NCC", "Prepared grayscale → recovered · normalized dot product"),
        )
        for index, (name, title, formula) in enumerate(metric_specs):
            card = tk.Frame(
                measures, bg=PALETTE["surface"],
                highlightbackground=PALETTE["border"],
                highlightthickness=1,
            )
            card.grid(
                row=index // 2, column=index % 2,
                sticky="nsew", padx=5, pady=5,
            )
            measures.grid_columnconfigure(index % 2, weight=1, uniform="metric")
            tk.Label(
                card, text=title, bg=PALETTE["surface"],
                fg=PALETTE["accent"], font=("Helvetica", 11, "bold"),
                anchor="w",
            ).pack(fill="x", padx=9, pady=(8, 2))
            value = tk.Label(
                card, text="Waiting for images", bg=PALETTE["surface"],
                fg=PALETTE["text"], font=("Helvetica", 16, "bold"),
                anchor="w", wraplength=160,
            )
            value.pack(fill="x", padx=9)
            self.metric_values[name] = value
            tk.Label(
                card, text=formula, bg=PALETTE["surface"],
                fg=PALETTE["muted"], font=("Helvetica", 9),
                anchor="w", justify="left", wraplength=160,
            ).pack(fill="x", padx=9, pady=(3, 8))

        tk.Label(
            content,
            text=("Scores evaluate outputs; they do not create the watermark. "
                  "There is no universal pass threshold. The Haar map shows "
                  "only the first 512 × 512 pixels at 2× and coefficient "
                  "changes at 4× for visualization. See the robustness study "
                  "for measured recovery under specified changes."),
            bg=PALETTE["background"], fg=PALETTE["text"],
            anchor="w", justify="left", wraplength=760,
        ).pack(fill="x", pady=(0, 9))

        self._section(content, "02  RESULT IMAGES · TRUE PIXELS")
        previews = tk.Frame(content, bg=PALETTE["background"])
        previews.pack(fill="x")

        captions = (
            ("cover", "Original image", "Choose an original image"),
            ("watermark", "Image to hide", "Choose an image to hide"),
            ("prepared", "Prepared watermark", "See the fitted watermark"),
            ("watermarked", "Watermarked image", "Embed to see the result"),
            ("extracted", "Recovered watermark", "Recover a watermark"),
            ("difference", "Difference · 4× display only", "See amplified changes"),
        )

        for index, (name, caption, placeholder) in enumerate(captions):
            panel = ImagePreview(
                previews,
                caption,
                pixelated=name in {"watermark", "prepared", "extracted"},
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
            panel.configure(height=400)
            panel.pack_propagate(False)

        for index in range(3):
            previews.grid_rowconfigure(index, weight=1)
        for index in range(2):
            previews.grid_columnconfigure(index, weight=1, uniform="preview")

        self._section(content, "03  ROBUSTNESS STUDY · MEASURED CASES")
        tk.Label(
            content,
            text=("Selected image pair fitted within 512 px. Classic, Balanced "
                  "and Durable × strengths 8/16/32 × sides 16/32/64. "
                  "Changes: unchanged PNG, JPEG 95/75/50, crop 5%/10% "
                  "from each edge, resize 75%/50%. Settings beyond "
                  "cover capacity are skipped."),
            bg=PALETTE["background"], fg=PALETTE["text"],
            anchor="w", justify="left", wraplength=760,
        ).pack(fill="x", pady=(3, 8))
        self.study_summary = self._study_table(
            content,
            ("Mode", "Change", "Exact", "Total", "Rate", "Header",
             "Incomplete", "Checksum", "Mean BER", "Mean NCC"),
            8,
        )
        self.study_details = self._study_table(
            content,
            ("Mode", "Strength", "Side", "Change", "Recovery",
             "PSNR dB", "Block SSIM", "BER", "NCC"),
            10,
        )
        self.study_note = tk.Label(
            content,
            text=("No study for this image pair yet. Exact rate counts only "
                  "checksum-verified, pixel-identical prepared marks. "
                  "N/A means extraction returned no watermark. Mean BER and "
                  "NCC use only cases with recovered pixels. "
                  "PSNR and block SSIM compare the working cover with "
                  "the watermarked image before each change."),
            bg=PALETTE["background"], fg=PALETTE["text"],
            anchor="w", justify="left", wraplength=760,
        )
        self.study_note.pack(fill="x", pady=(5, 12))

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
    def _study_table(parent, headings, height):
        frame = tk.Frame(parent, bg=PALETTE["background"])
        frame.pack(fill="x", pady=(0, 9))
        frame.grid_columnconfigure(0, weight=1)
        table = ttk.Treeview(
            frame, columns=headings, show="headings", height=height
        )
        for heading in headings:
            table.heading(heading, text=heading)
            table.column(heading, width=118, minwidth=90, stretch=False)
        vertical = ttk.Scrollbar(frame, orient="vertical", command=table.yview)
        horizontal = ttk.Scrollbar(frame, orient="horizontal", command=table.xview)
        table.configure(yscrollcommand=vertical.set, xscrollcommand=horizontal.set)
        table.grid(row=0, column=0, sticky="nsew")
        vertical.grid(row=0, column=1, sticky="ns")
        horizontal.grid(row=1, column=0, sticky="ew")
        return table

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
