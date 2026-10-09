"""Generate <=257-line paste files and a local deployment archive."""
from pathlib import Path
import zipfile

root = Path(__file__).resolve().parent
for path in [root / 'main.lua', root / 'install.lua', *sorted((root / 'lib').glob('*.lua')), *sorted((root / 'runtime').glob('*.lua'))]:
    source = path.read_text(encoding='utf-8')
    # Preserve all executable lines. Remove only whole-line comments/blanks.
    source = '\n'.join(line for line in source.splitlines() if line.strip() and not line.lstrip().startswith('--')) + '\n'
    assert len(source.splitlines()) <= 257, path
    output = root / 'paste' / path.relative_to(root)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(source, encoding='utf-8')
archive = root.parents[1] / 'outputs' / 'bec_v2_multinode.zip'
archive.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as out:
    guide = root.parents[1] / 'docs' / 'GETTING_STARTED.md'
    if guide.exists():
        out.write(guide, 'bec_v2/GETTING_STARTED.md')
    for path in [root / 'README.md', root / 'config.example.lua', root / 'main.lua', root / 'install.lua', *sorted((root / 'lib').glob('*.lua')), *sorted((root / 'runtime').glob('*.lua')), *sorted((root / 'paste').rglob('*.lua'))]:
        out.write(path, 'bec_v2/' + path.relative_to(root).as_posix())
print(archive)
