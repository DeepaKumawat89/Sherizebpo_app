
import sys
import re

# Try common encodings for Windows Gradle output
encodings = ['utf-16', 'utf-16le', 'utf-8', 'cp1252']

with open('sha_output.txt', 'w', encoding='utf-8') as out:
    for enc in encodings:
        try:
            with open('signing_report.txt', 'r', encoding=enc) as f:
                content = f.read()
                found = False
                for line in content.splitlines():
                    # Look for SHA1 or SHA-1 and SHA256 or SHA-256 followed by a colon or space
                    if re.search(r'SHA-?1[:\s]', line) or re.search(r'SHA-?256[:\s]', line):
                        out.write(line.strip() + '\n')
                        found = True
                if found:
                    break
        except (UnicodeDecodeError, FileNotFoundError):
            continue
