"""Compatibility import for image loading and verified PNG storage."""

import sys

from watermarking import image_io as _image_io

sys.modules[__name__] = _image_io
