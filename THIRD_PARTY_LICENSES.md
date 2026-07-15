# Third-Party Licenses

Echo is MIT-licensed (see `LICENSE`). It statically links the following
third-party library:

## Chromaprint

- **Used for:** acoustic fingerprinting (`Echo/core/services/Fingerprinter.swift`)
- **License:** GNU Lesser General Public License v2.1 (LGPL-2.1)
- **Source:** https://github.com/acoustid/chromaprint
- **Vendored as:** `vendor/Chromaprint.xcframework`, a static library
  built by `vendor/build-chromaprint.sh` from unmodified upstream
  source (version 1.6.0).

Echo statically links `libchromaprint.a` rather than linking dynamically. To
stay compliant with the LGPL-2.1's static-linking terms, Echo provides the
means to relink the app against a modified version of Chromaprint:

- The exact unmodified Chromaprint source used to build the vendored library
  is fetched by `vendor/build-chromaprint.sh` (pinned to v1.6.0 via
  the upstream GitHub release tarball) — nothing is patched.
- Echo's own object files are not obfuscated or license-restricted beyond
  the MIT license above; anyone may rebuild `Chromaprint.xcframework` from a
  modified Chromaprint source using the same script and relink it into Echo
  by building from source (`xcodebuild ... build`).
- The full LGPL-2.1 text is available at
  https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html.

Chromaprint's own build (invoked by `build-chromaprint.sh`) uses the bundled
KissFFT library for its FFT implementation:

## KissFFT

- **License:** BSD 3-Clause
- **Source:** https://github.com/mborgerding/kissfft
- **Note:** vendored inside Chromaprint's own source tree at build time (not
  checked into this repo); statically compiled into `libchromaprint.a`
  alongside Chromaprint itself.

Chromaprint's test suite (not built or shipped by Echo — `build-chromaprint.sh`
passes `-DBUILD_TOOLS=OFF` and only builds the `chromaprint` library target)
depends on **Google Test** (BSD 3-Clause, https://github.com/google/googletest).
It is not linked into Echo and is listed here only for completeness.
