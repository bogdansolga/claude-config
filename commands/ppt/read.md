---
command: ppt:read
description: Read text content from a .pptx by parsing it as an OOXML zip (no PowerPoint/LibreOffice needed)
---

## Description

Extracts the text of a PowerPoint `.pptx` file by treating it as an Open XML (OOXML) zip
archive and reading the slide XML directly. Works without PowerPoint, LibreOffice, or
`python-pptx` — only `python3` (stdlib `zipfile` + `re`) is required.

## Arguments

- `$ARGUMENTS` — path to the `.pptx` file to read. Quote it if it contains spaces.
  Optionally a slide number or range as a second token (e.g. `deck.pptx 3` or `deck.pptx 2-4`).

## How a .pptx is structured (what you need to know)

- A `.pptx` is a ZIP. Useful parts:
  - `[Content_Types].xml` — declares each part's MIME type (one `<Override>` per slide).
  - `ppt/presentation.xml` — `<p:sldIdLst>` lists slides **in display order** via `r:id`.
  - `ppt/_rels/presentation.xml.rels` — maps each `r:id` → `slides/slideN.xml`.
  - `ppt/slides/slideN.xml` — one slide. Text lives in `<a:t>...</a:t>` runs inside
    `<a:p>` paragraphs inside `<p:txBody>` of each shape (`<p:sp>`); tables use `<a:tbl>`.
  - `ppt/slides/_rels/slideN.xml.rels` — slide → its `slideLayout`, `notesSlide`, images, etc.
  - `ppt/notesSlides/notesSlideN.xml` — speaker notes (same `<a:t>` extraction).
  - `ppt/slideLayouts/`, `ppt/slideMasters/` — inherited placeholders/styling.
- `slideN.xml` numbering does **not** match display order — always resolve order through
  `presentation.xml` → `presentation.xml.rels`.
- XML entities in `<a:t>` must be unescaped: `&amp;`→`&`, `&lt;`→`<`, `&gt;`→`>`.

## Execution Steps

1. **Validate input** — confirm the path exists and ends in `.pptx`. If a slide number/range
   was given, remember it to filter output.

2. **Resolve slide order**
   ```python
   import zipfile, re
   path = "<file.pptx>"
   z = zipfile.ZipFile(path)
   pres = z.read("ppt/presentation.xml").decode("utf-8")
   rels = z.read("ppt/_rels/presentation.xml.rels").decode("utf-8")
   rid_to_target = dict(re.findall(r'Id="(rId\d+)"[^>]*Target="([^"]+)"', rels))
   order = [rid_to_target[m] for m in re.findall(r'<p:sldId[^>]*r:id="(rId\d+)"', pres)]
   # order is like ['slides/slide1.xml', 'slides/slide3.xml', ...] in display order
   ```

3. **Extract text per slide (and notes if asked)**
   ```python
   def texts(xml):
       out = []
       for t in re.findall(r'<a:t>(.*?)</a:t>', xml, re.S):
           out.append(t.replace('&amp;', '&').replace('&lt;', '<').replace('&gt;', '>'))
       return out
   for i, target in enumerate(order, 1):
       xml = z.read("ppt/" + target).decode("utf-8")
       print(f"=== Slide {i} ({target}) ===")
       for line in texts(xml):
           print(line)
   ```
   - For speaker notes: read `ppt/notesSlides/notesSlideN.xml` (find via the slide's
     `_rels/slideN.xml.rels` `notesSlide` relationship) and run the same `texts()` extractor.
   - Table cells are just more `<a:t>` runs, so they come through automatically (row structure
     is lost; if you need it, walk `<a:tr>`/`<a:tc>` instead).

4. **Present the result** — one block per slide, in display order, with the slide number and
   underlying `slideN.xml` filename (the filename is what `ppt:update` will need). If the user
   asked for a specific slide/range, show only those.

## Notes

- Read-only: never modify the file. To change a deck, use `/ppt:update`.
- If `<a:t>` extraction yields nothing for a slide, the text may be inside a chart, SmartArt
  (`ppt/diagrams/`), or an embedded image — note that to the user rather than silently skipping.
- Google-Slides-exported `.pptx` files have one `<a:t>` per run and Google may split a sentence
  across several runs; the extractor still prints them in reading order.
