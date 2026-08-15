from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()
stack = []
line = 1
col = 0
in_string = False
escape = False
in_comment = False
for ch in text:
    if ch == '\n':
        line += 1
        col = 0
        in_comment = False
        continue
    col += 1
    if in_comment:
        continue
    if in_string:
        if escape:
            escape = False
        elif ch == '\\':
            escape = True
        elif ch == '"':
            in_string = False
        continue
    if ch == ';':
        in_comment = True
        continue
    if ch == '"':
        in_string = True
        continue
    if ch == '(':
        stack.append((line, col))
    elif ch == ')':
        if stack:
            stack.pop()
        else:
            print('extra_close', line, col)
            raise SystemExit(1)
print('unclosed', stack[-20:])
