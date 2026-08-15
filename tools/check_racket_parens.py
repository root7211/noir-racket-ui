from pathlib import Path
p = Path('/home/ubuntu/noir_review/noir-racket-ui/noir/ui/main.rkt')
text = p.read_text()
depth = 0
in_string = False
escape = False
for lineno, line in enumerate(text.splitlines(), 1):
    i = 0
    while i < len(line):
        ch = line[i]
        if in_string:
            if escape:
                escape = False
            elif ch == '\\':
                escape = True
            elif ch == '"':
                in_string = False
        else:
            if ch == ';':
                break
            if ch == '"':
                in_string = True
            elif ch in '([':
                depth += 1
            elif ch in ')]':
                depth -= 1
                if depth < 0:
                    print(f'negative depth at line {lineno}: {line}')
                    raise SystemExit(1)
        i += 1
    if 3560 <= lineno <= 4100:
        print(f'{lineno:4} {depth:4} {line[:100]}')
print('final depth', depth)
