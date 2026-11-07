"""Compatibility import for the watermark engine."""

import sys

from watermarking import engine as _engine

sys.modules[__name__] = _engine
