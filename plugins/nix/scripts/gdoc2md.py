#!/usr/bin/env python3
"""Convert a Google Docs JSON body into Markdown matching md2gdoc.sh conventions."""
import json
import sys

HEADING_MAP = {
    "TITLE": "# ",
    "HEADING_1": "# ",
    "HEADING_2": "## ",
    "HEADING_3": "### ",
    "HEADING_4": "#### ",
    "HEADING_5": "##### ",
    "HEADING_6": "###### ",
}


def render_text(elements):
    """Concatenate textRun content with **bold** markers."""
    out = []
    for el in elements:
        tr = el.get("textRun")
        if not tr:
            continue
        content = tr.get("content", "")
        # Strip trailing newline; lines are joined by paragraph boundaries.
        if content.endswith("\n"):
            content = content[:-1]
        if not content:
            continue
        is_bold = (tr.get("textStyle", {}) or {}).get("bold")
        out.append(f"**{content}**" if is_bold else content)
    return "".join(out)


def render_paragraph(p):
    """Return (text, is_list_item, list_type) for a paragraph."""
    elements = p.get("elements", [])
    text = render_text(elements)
    style = (p.get("paragraphStyle") or {}).get("namedStyleType") or "NORMAL_TEXT"
    bullet = p.get("bullet")
    if bullet:
        # Determine numbered vs bullet by listId glyph type — fall back: assume bullet.
        # Without lists metadata we can't tell precisely; default to '-'.
        return text, True, "bullet"
    if style in HEADING_MAP:
        return HEADING_MAP[style] + text, False, None
    return text, False, None


def render_table(tbl):
    """Render a table to Markdown."""
    rows_data = []
    for row in tbl.get("tableRows", []):
        cells = []
        for cell in row.get("tableCells", []):
            cell_text_parts = []
            for c in cell.get("content", []):
                p = c.get("paragraph")
                if p:
                    cell_text_parts.append(render_text(p.get("elements", [])))
            cells.append(" ".join(t for t in cell_text_parts if t))
        rows_data.append(cells)
    if not rows_data:
        return ""
    ncols = max(len(r) for r in rows_data)
    rows_data = [r + [""] * (ncols - len(r)) for r in rows_data]
    lines = []
    header = rows_data[0]
    lines.append("| " + " | ".join(header) + " |")
    lines.append("|" + "|".join(["---"] * ncols) + "|")
    for r in rows_data[1:]:
        lines.append("| " + " | ".join(r) + " |")
    return "\n".join(lines)


def main():
    with open(sys.argv[1]) as f:
        body = json.load(f)
    out_lines = []
    prev_was_list = False
    for el in body:
        if "paragraph" in el:
            text, is_list, _ = render_paragraph(el["paragraph"])
            if is_list:
                out_lines.append(f"- {text}")
                prev_was_list = True
            else:
                if prev_was_list and text:
                    out_lines.append("")
                out_lines.append(text)
                prev_was_list = False
        elif "table" in el:
            if out_lines and out_lines[-1] != "":
                out_lines.append("")
            out_lines.append(render_table(el["table"]))
            out_lines.append("")
            prev_was_list = False
        elif "sectionBreak" in el:
            continue

    # Collapse runs of blank lines to max one blank between content
    collapsed = []
    blank_run = 0
    for line in out_lines:
        if line == "":
            blank_run += 1
            if blank_run <= 1:
                collapsed.append(line)
        else:
            blank_run = 0
            collapsed.append(line)

    print("\n".join(collapsed))


if __name__ == "__main__":
    main()
