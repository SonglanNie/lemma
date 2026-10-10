# Native PDFKit feasibility probe

Run on 30 September 2026 on a Mac with macOS 15.7.7, arm64, using the installed Swift toolchain and PDFKit. This is a short command-line research probe, not an application or a performance benchmark.

## Source and provenance

The PDF was obtained through [the ESL authors' download page](https://hastie.su.domains/ElemStatLearn/download.html), which links the corrected second-edition twelfth printing. The source remained temporary and is not included in this workspace.

- Source file: `ESLII_print12_toc.pdf`.
- PDFKit page count: 764.
- SHA-256: `8d098d65cf53925ba0fc13a52a2790d48a32433223cbd876d0a527cd1afe2e0f`.
- Temporary source location used for this run: `/tmp/lemma-research-2026-09-30/ESLII_print12_toc.pdf`.

## Observed results

The [probe](pdfkit_probe.swift) finds three pages using both a phrase and an equation number. It recovers native text, a text selection, page-space bounds, and individual line selections. It renders the page and a padded selection crop at three pixels per PDF point.

| Passage | Printed page | Physical page, one-based | PDFKit label | Physical index, zero-based | Selected lines |
| --- | --- | --- | --- | --- | --- |
| Least-squares uniqueness, equation 3.6 | 45 | 64 | 64 | 63 | 9 |
| Coefficient covariance, equation 3.8 | 47 | 66 | 66 | 65 | 21 |
| Ridge nonsingularity, equation 3.44 | 64 | 83 | 83 | 82 | 7 |

Each selected page has a crop box at `(72, 72)` with size `450 × 648` PDF points. The rendered page PNGs are `1350 × 1944` pixels. The exact selection bounds and text lengths are in [the saved observations](pdfkit-observations.json).

The native least-squares text includes this extraction of the displayed expression:

```text
ˆ
β = (XT X)−1XT y. (3.6)
```

The hat is a separate text item and the transpose/exponent structure is flattened in this text representation. The rendered source retains the mathematical appearance. Selection coordinates are useful even when the text is unsuitable as trusted LaTeX.

The printed-page 45 text also confirms a design matrix with `p+1` columns including the intercept. Other passages use different conventions. The covariance and ridge pages supply separate assumptions and contexts; the probe does not infer those relationships automatically.

Visual inspection covered the native full page for the least-squares passage and the three padded crops. A Poppler rendering of physical page 64 provided an additional visual comparison for the least-squares page after correcting the native drawing transform. No pixel-equality assertion was made.

## A concrete geometry lesson

In this test, `PDFPage.draw(with: .cropBox, to:)` already positioned the chosen display box. Applying a second translation by its origin shifted and clipped the output. Removing that extra translation restored the page position.

The script maps selection bounds from PDF page space into upper-left-origin image coordinates when cropping. This was checked for these unrotated pages. It is not a tested universal conversion for rotations, mixed page boxes, or PDFView screen coordinates.

The selected crops are padded text-range bounds, not automatically detected complete equations or paragraphs. A crop can include only part of adjacent context; production region selection should let the reader inspect and adjust what is included.

## Reproduce

Obtain the same source through the authors' page, then run from the Lemma workspace:

```bash
swift research/pdfkit_probe.swift /path/to/ESLII_print12_toc.pdf /tmp/lemma-pdfkit-probe
```

Inspect the emitted `*-page.png` and `*-selection.png` files beside the extracted `*-native.txt` files and `report.json`. The probe overwrites only its own named output files in the chosen directory; use a separate output directory for each source/run.

The independent Poppler comparison used:

```bash
pdftoppm -f 64 -l 64 -cropbox -r 216 -png -singlefile \
  /path/to/ESLII_print12_toc.pdf /tmp/lemma-esl-page45
```

These small commands completed quickly. Any later whole-library conversion, model evaluation, or other long or heavy job should run at background priority, and not on battery.

## What this establishes

Native access to this PDF's text, line selections, page geometry, and rendered regions works on the current Mac. A first version can use these primitives without a mathematical OCR model.

It does not establish interactive viewer correctness, arbitrary PDF compatibility, OCR quality, semantic symbol resolution, proof checking, persistence, browser attachment behavior, ChatGPT access, or a measurable improvement in learning. Those claims require their own evidence.
