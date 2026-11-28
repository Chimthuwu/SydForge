"""Turns web/build (Godot's export) into web/dist, ready for Cloudflare Pages.

Pages rejects files over 25 MiB, so index.pck and index.wasm are gzipped and
split into parts. A small script in index.html reassembles them when the engine
asks for them. Run after exporting:  python web/package.py
"""
import gzip
import json
import pathlib
import shutil

HERE = pathlib.Path(__file__).parent
BUILD, DIST = HERE / 'build', HERE / 'dist'
PART = 20 * 1024 * 1024
BIG = {'index.pck': 'application/octet-stream', 'index.wasm': 'application/wasm'}

shutil.rmtree(DIST, ignore_errors=True)
DIST.mkdir()
manifest = {}
for source in BUILD.iterdir():
    if source.name not in BIG:
        if source.suffix != '.import':
            shutil.copy2(source, DIST / source.name)
        continue
    raw = source.read_bytes()
    packed = gzip.compress(raw, 9)
    parts = []
    for offset in range(0, len(packed), PART):
        name = '%s.gz.%02d' % (source.name, len(parts))
        (DIST / name).write_bytes(packed[offset:offset + PART])
        parts.append(name)
    manifest[source.name] = {'parts': parts, 'type': BIG[source.name], 'size': len(raw)}
    print(source.name, len(raw), '->', len(packed), 'in', len(parts), 'parts')

loader = '''<script>
(() => {
  const files = %s;
  const original = window.fetch.bind(window);
  window.fetch = async (input, init) => {
    const url = typeof input === 'string' ? input : input.url;
    const name = new URL(url, location.href).pathname.split('/').pop();
    const file = files[name];
    if (!file) return original(input, init);
    const blobs = await Promise.all(file.parts.map(async (part) => {
      const response = await original(part);
      if (!response.ok) throw new Error('Could not download ' + part);
      return response.blob();
    }));
    const body = new Blob(blobs).stream().pipeThrough(new DecompressionStream('gzip'));
    return new Response(body, { headers: { 'Content-Type': file.type, 'Content-Length': String(file.size) } });
  };
})();
</script>
''' % json.dumps(manifest)

page = (DIST / 'index.html').read_text(encoding='utf8')
marker = '<script src="index.js"></script>'
assert marker in page, 'Godot page layout changed'
(DIST / 'index.html').write_text(page.replace(marker, loader + marker), encoding='utf8')
largest = max(DIST.iterdir(), key=lambda f: f.stat().st_size)
assert largest.stat().st_size < 25 * 1024 * 1024, largest
print('ready:', DIST)
