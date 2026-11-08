# MATLAB Haar Wavelet Watermarking App

This project uses a MATLAB GUI to hide a grayscale image watermark inside a cover image, recover it, and evaluate the result.

## Requirements

- Desktop MATLAB with support for `uifigure` and `uigridlayout`.
- Image Processing Toolbox.
- The complete project folder, including [matlab/source/images](matlab/source/images/) for the built-in examples.

## Run the app

1. Unzip or download the complete project folder.
2. Open MATLAB and set **Current Folder** to the project's [matlab](matlab/) folder, which contains [runWatermarkApp.m](matlab/runWatermarkApp.m).
3. Enter this command in the MATLAB Command Window:

   ```matlab
   runWatermarkApp
   ```

The **Wavelet Watermark Studio** window should open. If MATLAB cannot find `runWatermarkApp`, check that **Current Folder** is the `matlab` folder and enter the command again.

## Create a watermarked image

1. In **Create**, select **Try an example** to load bundled images and create a result automatically. To choose your own images, select **Choose original image** and **Choose image to hide**.
2. For a manual example, use [cover-1.jpg](test-images/cover-1.jpg) or [cover-2.jpg](test-images/cover-2.jpg) as the original image, and [watermark-1.jpg](test-images/watermark-1.jpg) or [watermark-2.jpg](test-images/watermark-2.jpg) as the image to hide.
3. Choose the watermark strength, hidden image size, and **Balanced**, **Durable**, or **Classic** mode. Check the capacity message before continuing.
4. Select **Create watermarked image**. The app displays the original image, prepared watermark, watermarked image, recovered watermark, and quality scores.
5. Select **Save watermarked PNG** to keep the result. You can also select **Save recovered watermark** to save the extracted image.

## Recover a watermark later

1. Open the **Extract** tab and select **Open saved watermarked PNG**.
2. Choose the unchanged PNG produced by **Save watermarked PNG**. The app reads the embedded settings and displays the recovered watermark automatically.
3. Select **Save recovered watermark** if you want a separate PNG of the extracted image.

To repeat extraction while the created image is still open, select **Recover current image** in the **Extract** tab. Keep the saved PNG unchanged because JPEG conversion, cropping, or resizing may prevent exact recovery.

## Evaluate the result

With both input images selected, open **Evaluate** and select **Run study on selected images**. The study tests the three embedding modes, several strengths and watermark sizes, unchanged PNG, JPEG compression, cropping, and resizing. Its tables show exact recovery rates, quality scores, bit error rates, and recovery states. Settings that exceed image capacity are skipped.

The **Details** tab shows the current image dimensions, selected settings, capacity, saved path, and quality and recovery measures. PSNR and block SSIM compare the cover with the watermarked image; BER and NCC compare the prepared and recovered watermarks when both are available.

## Optional project checks

From the [matlab](matlab/) folder, run the MATLAB tests and Code Analyzer checks with:

```matlab
runProjectChecks
```

## Sample image credits

The four images in [test-images](test-images/) come from Unsplash:

| Local image | Photo source |
| --- | --- |
| [cover-1.jpg](test-images/cover-1.jpg) | [Mountain lake and trees](https://unsplash.com/photos/nxPucjyxWqg) |
| [cover-2.jpg](test-images/cover-2.jpg) | [Forest beside a lake](https://unsplash.com/photos/JXt8HYZqf3M) |
| [watermark-1.jpg](test-images/watermark-1.jpg) | [City skyline](https://unsplash.com/photos/a8WZxtfrgs4) |
| [watermark-2.jpg](test-images/watermark-2.jpg) | [Namib desert dunes](https://unsplash.com/photos/AflZC9OVS9A) |

## What the project does and how to test it

**Main point:** The app hides one image inside another with a Haar wavelet transform, then checks whether it can recover the hidden image.

1. **Choose the images.**
   - Load a cover image and an image to hide, or select **Try an example** for a quick test.
   - The app prepares the hidden image as a small grayscale watermark.
2. **Set and embed the watermark.**
   - Choose its strength, size, and mode, then check that the cover has enough capacity.
   - Select **Create watermarked image** to embed the watermark and see the recovered result.
3. **Check the first result.**
   - Compare the prepared and recovered watermarks in the GUI.
   - Open **Details** and check the recovery status, BER, and NCC; use PSNR and block SSIM to inspect cover quality.
4. **Test saved-image recovery.**
   - Save the watermarked image as PNG, then open that same file from **Extract**.
   - Check that the app displays the recovered watermark and its verification status; save the recovered watermark if needed.
5. **Test image changes.**
   - With both input images selected, run the **Evaluate** study to test compression, cropping, and resizing.
   - Compare exact recovery rates and failure states across settings; these changes may prevent recovery.
