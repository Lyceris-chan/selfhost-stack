with open('lib/services/compose.sh', 'r') as f:
    in_quote = False
    for i, line in enumerate(f, 1):
        # Ignore comments for simple check, though quotes in comments are fine
        # but let's just count all single quotes not preceded by backslash
        quotes = 0
        escaped = False
        for char in line:
            if char == '\\':
                escaped = not escaped
            elif char == "'" and not escaped:
                in_quote = not in_quote
                escaped = False
            else:
                escaped = False
        if in_quote:
            print(f"Line {i}: state is IN_QUOTE")
