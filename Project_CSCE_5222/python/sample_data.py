"""Compatibility import for bundled example images."""

import sys

from watermarking import examples as _examples

sys.modules[__name__] = _examples
