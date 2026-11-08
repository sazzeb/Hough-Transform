# How to run this project from a ZIP file

1. Unzip the project. Keep the `matlab` and `python` folders together with the four sample images.
2. Choose **MATLAB** or **Python in VS Code** below. You only need one of them to use the app.

## Run with MATLAB on Windows, macOS, or Linux

1. Install desktop MATLAB with the Image Processing Toolbox. Use a recent R20xx release that supports `uifigure`.
2. Open MATLAB. In the **Current Folder** panel, open the unzipped project's [matlab](matlab/) folder.
3. In the MATLAB Command Window, enter:

   ```matlab
   runWatermarkApp
   ```
4. The app window opens. If MATLAB says it cannot find the function, check that **Current Folder** is the `matlab` folder, then run the command again.

You can also open the project folder in VS Code to read or edit MATLAB files. Run the command above in MATLAB; VS Code alone does not run MATLAB code.

## Run Python in VS Code on Windows

1. Install Python 3.11 or newer and VS Code. In VS Code, install the **Python** extension.
2. Open the unzipped project folder in VS Code. Open **Terminal → New Terminal**.
3. Enter these commands, one line at a time:

   ```powershell
   py -3 -m venv .venv
   .\.venv\Scripts\Activate.ps1
   python -m pip install -r python\requirements.txt
   python python\watermark_app.py
   ```
4. If PowerShell blocks activation, open a **Command Prompt** terminal in VS Code and use `.venv\Scripts\activate.bat` instead. Then run the last two commands again.

## Run Python in VS Code on macOS or Linux

1. Install Python 3.11 or newer and VS Code. In VS Code, install the **Python** extension.
2. Open the unzipped project folder in VS Code. Open **Terminal → New Terminal**.
3. Enter these commands, one line at a time:

   ```sh
   python3 -m venv .venv
   source .venv/bin/activate
   python -m pip install -r python/requirements.txt
   python python/watermark_app.py
   ```
4. On Linux, if Python reports that `tkinter` is missing, install your system's Tk package (often `python3-tk`) and try again.

**iPhone and iPad:** iOS cannot run this desktop GUI. If you meant **macOS**, use the macOS steps above.

## Try the app

1. Click **Try an example**, or click **Choose original image** and select [cover-1.jpg](cover-1.jpg) or [cover-2.jpg](cover-2.jpg).
2. Click **Choose image to hide** and select [watermark-1.jpg](watermark-1.jpg) or [watermark-2.jpg](watermark-2.jpg).
3. Set the strength, watermark size, and mode. Click **Create watermarked image**.
4. View the original, prepared watermark, watermarked image, recovered watermark, and quality scores.
5. Click **Save watermarked PNG** to keep the result. To recover it later, open **Extract** and select that same saved PNG. You can also save the recovered watermark.

Keep the saved PNG unchanged. Converting it to JPEG, cropping it, or resizing it can stop exact recovery.

## What this project does

This project hides one image inside another with a Haar wavelet transform. The first image is the **cover**. The second image is prepared as a small grayscale **watermark**. The app puts that watermark into wavelet detail values of the cover, then reads it back from the saved PNG.

The GUI lets you load images, change strength and size, create and extract a watermark, view each step, and save the results. PSNR and SSIM show changes to the cover. BER and NCC compare the recovered watermark with the prepared watermark when both are available. A successful check on an unchanged PNG does not promise recovery after JPEG compression, cropping, or resizing.

The four root sample photos come from Unsplash:

| Local file                        | Photo source                                                      |
| --------------------------------- | ----------------------------------------------------------------- |
| [cover-1.jpg](cover-1.jpg)         | [Mountain lake and trees](https://unsplash.com/photos/nxPucjyxWqg) |
| [cover-2.jpg](cover-2.jpg)         | [Forest beside a lake](https://unsplash.com/photos/JXt8HYZqf3M)    |
| [watermark-1.jpg](watermark-1.jpg) | [City skyline](https://unsplash.com/photos/a8WZxtfrgs4)            |
| [watermark-2.jpg](watermark-2.jpg) | [Namib desert dunes](https://unsplash.com/photos/AflZC9OVS9A)      |
