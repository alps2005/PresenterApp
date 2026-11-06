#!/usr/bin/env python3
"""Checks that every T("…") in the Windows app has a Spanish translation in SpanishStrings.cs that keeps its {n}
placeholders, and that the table has nothing the app no longer uses. Run by CI before the Windows build."""
import pathlib
import re
import sys

app = pathlib.Path(__file__).resolve().parent.parent / "Windows" / "Presenter.Windows"
literal = re.compile(r'"((?:[^"\\]|\\.)*)"')
call = re.compile(r'\bT\(\s*((?:"(?:[^"\\]|\\.)*"\s*\+?\s*)+)')

def unescape(text):
    return text.replace('\\n', '\n').replace('\\"', '"').replace('\\\\', '\\')

used = set()
for source in app.glob("*.cs"):
    if source.name == "SpanishStrings.cs":
        continue
    code = source.read_text(encoding="utf-8")
    for match in call.finditer(code):
        used.add(unescape("".join(literal.findall(match.group(1)))))
# Section names are translated through a variable: T(name) over Settings.SectionKinds.
kinds = (app / "Settings.cs").read_text(encoding="utf-8")
used.update(unescape(name) for name in re.findall(r'\("\w+", "([^"]+)"\)', kinds))

table = {}
for line in (app / "SpanishStrings.cs").read_text(encoding="utf-8").splitlines():
    entry = re.match(r'\s*\[("(?:[^"\\]|\\.)*")\] = ("(?:[^"\\]|\\.)*"),\s*$', line)
    if entry:
        table[unescape(entry.group(1)[1:-1])] = unescape(entry.group(2)[1:-1])

placeholders = lambda text: sorted(re.findall(r"\{\d+\}", text))
problems = [f"no Spanish for {key!r}" for key in sorted(used - table.keys())]
problems += [f"unused translation for {key!r}" for key in sorted(table.keys() - used)]
problems += [f"placeholders differ in {key!r}" for key in sorted(used & table.keys())
             if placeholders(key) != placeholders(table[key])]
for problem in problems:
    print(problem)
print(f"{len(used)} strings, {len(table)} translations, {len(problems)} problems")
sys.exit(1 if problems else 0)
