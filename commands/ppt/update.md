---
command: ppt:update
description: Edit text in or append slides to a .pptx by manipulating its OOXML zip directly (no PowerPoint/LibreOffice needed)
---

## Description

Modifies a PowerPoint `.pptx` by editing the underlying Open XML (OOXML) parts: change the
text of an existing shape, or append new slides cloned from an existing layout. Uses only
`python3` (stdlib `zipfile`, `re`, `shutil`, `xml.dom.minidom`) — no PowerPoint, LibreOffice,
or `python-pptx`.

## Arguments

- `$ARGUMENTS` — path to the `.pptx` file to update, plus a short description of the change
  (e.g. `"deck.pptx update slide 7 numbers"` or `"deck.pptx append a Top 3 Risks slide"`).
  Quote paths with spaces. If the change isn't fully specified, ask the user before editing.

## Hard rules

1. **Back up first.** Copy the original to `/tmp/<name>.ORIGINAL_backup.pptx` (or `<name>.bak`)
   before touching anything. State where the backup is.
2. **Work in a temp extraction dir**, never edit the zip in place. Repackage to a new file,
   validate, then move it over the original.
3. **Validate before delivering**: `zipfile.ZipFile(out).testzip()` must return `None`, and
   every XML part you changed must parse with `xml.dom.minidom.parseString(...)`.
4. **You cannot render the file here** (no PowerPoint/LibreOffice). After delivering, explicitly
   tell the user you only validated structurally and ask them to open it to confirm layout /
   that nothing overflows.
5. Preserve part order on repackage — write `[Content_Types].xml` first (it's first in the
   original `namelist()`), then the rest in original order, then any new parts.

## Recap of the .pptx structure

- ZIP. `ppt/presentation.xml` `<p:sldIdLst>` = display order via `r:id`;
  `ppt/_rels/presentation.xml.rels` maps `r:id` → `slides/slideN.xml`.
- `ppt/slides/slideN.xml`: shapes are `<p:sp>`, each with `<p:nvSpPr><p:cNvPr id="N" name="...">`.
  Text = `<p:txBody>` → `<a:p>` paragraphs → `<a:r>` runs → `<a:t>text</a:t>`.
  Paragraph level/bullet/spacing live in `<a:pPr>` (`lvl="0"`, `<a:buChar char="●"/>`, etc.);
  run formatting in `<a:rPr>` (`b="1"`, `sz="1000"` = 10pt, `<a:solidFill>`, `<a:latin typeface=.../>`).
- `ppt/slides/_rels/slideN.xml.rels`: slide → its `slideLayout` (required), `notesSlide`, images.
- `[Content_Types].xml`: one `<Override ... PartName="/ppt/slides/slideN.xml"/>` per slide;
  `.rels` and `.xml` extensions are covered by `<Default>` entries (so new `.rels` need no Override).
- Escape text going into `<a:t>`: `&`→`&amp;`, `<`→`&lt;`, `>`→`&gt;`.

## Mode A — edit text of an existing shape/slide

1. `/ppt:read` the deck (or extract and grep `<a:t>`) to find the target slide's `slideN.xml`
   and the shape — identify it by its `<p:cNvPr id="...">` or by a unique text run it contains.
2. Smallest change = swap text inside the existing `<a:t>` element(s):
   `xml = xml.replace('<a:t>OLD</a:t>', '<a:t>NEW</a:t>')` (escape NEW). Keep the run's `<a:rPr>`
   so formatting is preserved. If a run is split mid-sentence (common in Google exports), edit
   each piece.
3. Bigger change (restructure a bulleted list) = rebuild that shape's whole `<p:txBody>`.
   Mirror the `<a:pPr>`/`<a:rPr>` of the slide's existing paragraphs so the new ones inherit the
   same look. Helper pattern for a bulleted paragraph:
   ```python
   FONT = ('<a:latin typeface="Open Sans"/><a:ea typeface="Open Sans"/>'
           '<a:cs typeface="Open Sans"/><a:sym typeface="Open Sans"/>')
   def esc(t): return t.replace("&","&amp;").replace("<","&lt;").replace(">","&gt;")
   def para(text, lvl=1, bold=False, sz=900, bullet="○"):
       b = "1" if bold else "0"
       marL = "457200" if lvl == 0 else "914400"
       return (f'<a:p><a:pPr indent="-285750" lvl="{lvl}" marL="{marL}" marR="0" rtl="0" algn="l">'
               f'<a:lnSpc><a:spcPct val="110000"/></a:lnSpc><a:spcBef><a:spcPts val="0"/></a:spcBef>'
               f'<a:spcAft><a:spcPts val="0"/></a:spcAft><a:buClr><a:schemeClr val="dk1"/></a:buClr>'
               f'<a:buSzPts val="{sz}"/><a:buFont typeface="Open Sans"/><a:buChar char="{bullet}"/></a:pPr>'
               f'<a:r><a:rPr b="{b}" i="0" lang="en" sz="{sz}" u="none" cap="none" strike="noStrike">'
               f'<a:solidFill><a:schemeClr val="dk1"/></a:solidFill>{FONT}</a:rPr><a:t>{esc(text)}</a:t></a:r>'
               f'<a:endParaRPr b="{b}" i="0" sz="{sz}" u="none" cap="none" strike="noStrike">'
               f'<a:solidFill><a:schemeClr val="dk1"/></a:solidFill>{FONT}</a:endParaRPr></a:p>')
   ```
   Replace the shape's body with a regex anchored on its `cNvPr id`:
   ```python
   m = re.search(r'(<p:sp><p:nvSpPr><p:cNvPr id="558".*?</p:spPr>)<p:txBody>.*?</p:txBody>(</p:sp>)', xml, re.S)
   xml = xml[:m.start()] + m.group(1) + new_txbody + m.group(2) + xml[m.end():]
   ```
   Build f-strings/concatenation for XML — **don't** use `%`-formatting over strings that contain
   literal `%` (e.g. "% time saved") or it will raise `TypeError: not enough arguments`.
4. If you changed the number of `<a:p>` in a shape that has per-paragraph build animations,
   strip the slide's `<p:timing>...</p:timing>` block (`re.sub(r'<p:timing>.*?</p:timing>','',xml,flags=re.S)`)
   — stale animation targets cause PowerPoint "repair" prompts. Mention you removed the animation.
5. If text now overflows the box, either shrink `<a:lnSpc>`/`sz`, or grow/move the shape's
   `<a:off>`/`<a:ext>` in EMUs (914400 EMU = 1 inch; default slide = 9144000 × 5143500 unless
   `<p:sldSz>` says otherwise — check it).

## Mode B — append a new slide

1. Pick a **template slide** to clone — an existing slide with a simple title + bulleted body
   (look for one using a "Title and Content"-style `slideLayout`). Note its `slideLayoutNN.xml`
   from its `_rels`.
2. Decide the new numbers: `K = (max existing slideN) + 1`; pick a fresh `r:Id` not already in
   `presentation.xml.rels` (e.g. `rId37`); pick a fresh `<p:sldId>` `id` (existing ones are
   ≥256; use `max + 1`). Use shape `id`s that don't collide (large numbers like 900+ are safe).
3. Write `ppt/slides/slideK.xml`. Minimum viable slide:
   ```xml
   <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
   <p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
          xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
          xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
     <p:cSld><p:spTree>
       <p:nvGrpSpPr><p:cNvPr id="900" name="Shape 900"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
       <p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>
       <!-- body text box: <p:sp> with <p:cNvSpPr txBox="1"/>, <p:nvPr/>, <a:xfrm> position, and a <p:txBody> of <a:p> paragraphs (reuse pPr/rPr copied from the template slide) -->
       <!-- title: <p:sp> with <p:nvPr><p:ph type="ctrTitle"/></p:nvPr> and a single <a:p> run -->
     </p:spTree></p:cSld>
     <p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>
   </p:sld>
   ```
   Easiest: copy the template `slideN.xml` verbatim, then (a) replace the `<p:txBody>` of its
   body shape and title run with your content, (b) bump all `<p:cNvPr id>` to unique values,
   (c) delete its `<p:timing>` block. Keep the full xmlns list from the original `<p:sld>`.
4. Write `ppt/slides/_rels/slideK.xml.rels` pointing at the same layout:
   ```xml
   <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
   <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
     <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayoutNN.xml"/>
   </Relationships>
   ```
   (A `notesSlide` relationship is optional — omit it.)
5. Register the slide in three places:
   - `ppt/_rels/presentation.xml.rels`: add
     `<Relationship Id="rId37" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slideK.xml"/>`
     before `</Relationships>`.
   - `ppt/presentation.xml`: add `<p:sldId id="<fresh>" r:id="rId37"/>` inside `<p:sldIdLst>`
     (position = where you want it in display order; append before `</p:sldIdLst>` for last).
   - `[Content_Types].xml`: add
     `<Override ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml" PartName="/ppt/slides/slideK.xml"/>`
     before `</Types>`.
6. Repackage and validate (see Hard rules). Repeat steps 3–5 for each extra slide with new numbers.

## Repackage + validate snippet

```python
import zipfile, xml.dom.minidom as M
out = "/tmp/<name>_new.pptx"
with zipfile.ZipFile(SRC) as z: names = z.namelist()           # original part order
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zo:
    for n in names: zo.write(os.path.join(WORK, n), n)         # [Content_Types].xml is names[0]
    for n in NEW_PARTS: zo.write(os.path.join(WORK, n), n)
with zipfile.ZipFile(out) as z:
    assert z.testzip() is None
    for n in CHANGED_OR_NEW_XML: M.parseString(z.read(n))      # well-formedness
# then: cp original -> backup; cp out -> original path
```

## Notes

- Keep edits minimal — preserve existing `<a:pPr>`/`<a:rPr>` so theme/fonts survive.
- Google-Slides exports keep a `metadata` part and a `GoogleSlidesCustomData` ext in
  `presentation.xml`; leave them alone, they don't block adding slides.
- After delivering: report slide count, where the backup is, anything you removed (e.g.
  animations), and that the user should open it to eyeball the result since it wasn't rendered.
- For read-only inspection use `/ppt:read`.
