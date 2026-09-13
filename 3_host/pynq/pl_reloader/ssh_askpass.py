#!/usr/bin/env python3
"""Minimal SSH_ASKPASS helper for the packaged PL reloader."""

from __future__ import annotations

import os
import sys


PASSWORD_ENV = "EES331_SSH_PASSWORD"


def main() -> int:
    password = os.environ.get(PASSWORD_ENV)
    if password is None:
        return 1
    sys.stdout.write(password)
    sys.stdout.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
