"""Launch the desktop app and preserve its original import path."""

import sys

from watermarking import app as _app

if __name__ == "__main__":
    _app.main()
else:
    sys.modules[__name__] = _app
