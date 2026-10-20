"""
media_page.py - write media/renders/plan.html from media/renders/budget.json
(made by media_lab.py): every planned item with its render, its size, and a
budget you can play with (tick items on / off).

    python tools/media_page.py

Open media/renders/plan.html in a browser (it plays the renders next to it).
The page stays on this PC: it holds friends' photos and other people's videos.
"""
import html
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from media_plan import PLAN  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'media', 'renders')
FREE = 7_340_032

MODE = {
    'bg': 'background: whole screen behind the game (blocks stay solid)',
    'full': 'whole screen, covers the game, result text on top',
    'over': 'on top of the game, green screen see-through',
    'panel': 'picture in the right panel (2x)',
    '': '',
}
GROUPS = [
    ('music', 'In-game music', 'Plays from the flash during a round, one after the other (a playlist), '
              'and stops while a media attack plays its own sound.'),
    ('attack', 'Media attacks', 'New chaos attacks you send to the rival: the video plays behind their game '
               '(everywhere except on the blocks) and its sound replaces their music. Each board counts down the '
               'length of the media attack it sent, plus a gap, and does not send another until then, so they never '
               'come back to back.'),
    ('sprite', 'Sprites', 'Small pictures drawn on top of everything: Jevil during his attack, '
               'and your friends\' faces on the BOUNCERS attack instead of plain squares.'),
    ('lose', 'When you lose (one picked at random)', ''),
    ('win', 'When you win (one picked at random)', ''),
]


def esc(s):
    return html.escape(str(s))


def card(d, it):
    files = d.get('files', [])
    media = ''
    scene = next((f for f in files if f.endswith('_scene.mp4')), None)
    clip = next((f for f in files if f.endswith('_clip.mp4')), None)
    png = next((f for f in files if f.endswith('.png')), None)
    wav = next((f for f in files if f == d['id'] + '.wav'), None)
    if scene:
        media = f'<video controls preload="metadata" src="{esc(scene)}"' + (f' poster="{esc(png)}"' if png else '') + '></video>'
    elif png:
        media = f'<img src="{esc(png)}" alt="{esc(d["title"])} on the game screen">'
    if wav and not scene:
        media += f'<audio controls preload="none" src="{esc(wav)}"></audio>'
    facts = []
    if d.get('mode'):
        facts.append(MODE[d['mode']])
    if d.get('bpp'):
        facts.append(f"{d['bpp']} bit{'s' if d['bpp'] > 1 else ''} per pixel = {1 << d['bpp']} colours")
    if d.get('fps'):
        facts.append(f"{d['fps']} pictures a second")
    if it.get('loop'):
        facts.append(f"a {it['loop'][1]:g} s video loop under the {d.get('seconds', '?')} s of sound")
    elif d.get('seconds'):
        facts.append(f"{d['seconds']} s")
    if d.get('rate'):
        facts.append(f"sound {d['rate'] // 1000} kHz ADPCM")
    if d.get('video_raw'):
        facts.append(f"picture squeezed {d['video_raw'] / max(1, d['video_bytes']):.1f}x by the delta + run-length format")
    extra = f' · <a href="{esc(clip)}">the clip alone</a>' if clip else ''
    return f'''
    <article class="item" data-id="{esc(d['id'])}">
      <div class="media">{media}</div>
      <div class="meta">
        <label class="pick"><input type="checkbox" id="k_{esc(d['id'])}" data-bytes="{d['bytes']}" {'checked' if d['keep'] else ''}>
          <span class="t">{esc(d['title'])}</span></label>
        <div class="size">{d['bytes'] / 1024:,.0f} KB</div>
        <ul>{''.join(f'<li>{esc(f)}</li>' for f in facts)}</ul>
        <div class="note">{esc(d['id'])}{extra}</div>
      </div>
    </article>'''


def main():
    res = {d['id']: d for d in json.load(open(os.path.join(OUT, 'budget.json'), encoding='utf-8'))}
    plan = {p['id']: p for p in PLAN}
    sections = []
    for g, title, intro in GROUPS:
        cards = ''.join(card(res[p['id']], p) for p in PLAN if p['group'] == g and p['id'] in res)
        sections.append(f'''
  <section id="{g}">
    <h2>{esc(title)}</h2>
    {f'<p>{esc(intro)}</p>' if intro else ''}
    <div class="grid">{cards}</div>
  </section>''')
    page = TEMPLATE.replace('%SECTIONS%', ''.join(sections)).replace('%FREE%', str(FREE))
    open(os.path.join(OUT, 'plan.html'), 'w', encoding='utf-8').write(page)
    print('wrote', os.path.join(OUT, 'plan.html'))


TEMPLATE = r'''<meta charset="utf-8">
<title>Tetris Duel Media Plan</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Chakra+Petch:wght@500;600;700&family=IBM+Plex+Sans:wght@400;500;600&family=IBM+Plex+Mono:wght@400;500&display=swap">
<style>
/* One column of decisions: a sticky flash-budget bar on top, then each group of media as cards
   (render on the left, settings and size on the right). */
:root {
  --bg: #f3f4f7; --panel: #ffffff; --fg: #151922; --muted: #5a6273; --line: #d9dde5;
  --accent: #007f8f; --accent-soft: #d5eef1; --warn: #c25e00; --bad: #c8283e;
  --display: "Chakra Petch", "Segoe UI", system-ui, sans-serif;
  --body: "IBM Plex Sans", "Segoe UI", system-ui, sans-serif;
  --mono: "IBM Plex Mono", ui-monospace, Consolas, monospace;
}
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) {
  --bg: #0e1116; --panel: #161a21; --fg: #e5e8ee; --muted: #9aa3b2; --line: #2a303b;
  --accent: #3fc3d3; --accent-soft: #123a40; --warn: #f0954a; --bad: #ff5d72; color-scheme: dark } }
:root[data-theme="dark"] {
  --bg: #0e1116; --panel: #161a21; --fg: #e5e8ee; --muted: #9aa3b2; --line: #2a303b;
  --accent: #3fc3d3; --accent-soft: #123a40; --warn: #f0954a; --bad: #ff5d72; color-scheme: dark }
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--fg); font: 16px/1.6 var(--body); }
main { max-width: 1100px; margin: 0 auto; padding-block: 24px 80px;
  padding-left: max(16px, env(safe-area-inset-left, 0px)); padding-right: max(16px, env(safe-area-inset-right, 0px));
  display: flex; flex-direction: column; gap: 40px; }
h1, h2, h3 { font-family: var(--display); line-height: 1.2; text-wrap: balance; margin: 0; }
h1 { font-size: clamp(28px, 4vw, 40px); }
h2 { font-size: clamp(22px, 3vw, 28px); }
p { margin: 0; max-width: 72ch; }
section { display: flex; flex-direction: column; gap: 14px; }
code { font-family: var(--mono); font-size: .9em; }
.bar { position: sticky; top: env(safe-area-inset-top, 0px); z-index: 2; background: var(--panel); border: 1px solid var(--line);
  border-radius: 8px; padding: 12px 16px; display: flex; flex-direction: column; gap: 8px; }
.bar .row { display: flex; flex-wrap: wrap; gap: 6px 18px; align-items: baseline; font-family: var(--mono); font-size: 14px; }
.bar .big { font-family: var(--display); font-size: 22px; font-weight: 600; }
.meter { height: 14px; background: var(--line); border-radius: 7px; overflow: hidden; }
.meter i { display: block; height: 100%; background: var(--accent); width: 0; transition: width .2s; }
.meter.over i { background: var(--bad); }
.grid { display: flex; flex-direction: column; gap: 12px; }
.item { display: grid; grid-template-columns: minmax(0, 480px) minmax(0, 1fr); gap: 16px; background: var(--panel);
  border: 1px solid var(--line); border-radius: 8px; padding: 12px; }
@media (max-width: 760px) { .item { grid-template-columns: minmax(0, 1fr); } }
.media video, .media img { width: 100%; max-width: 480px; display: block; border-radius: 4px; background: #000; image-rendering: pixelated; }
.media audio { width: 100%; margin-top: 6px; }
.meta { display: flex; flex-direction: column; gap: 6px; min-width: 0; }
.pick { display: flex; gap: 10px; align-items: center; cursor: pointer; }
.pick input { width: 18px; height: 18px; accent-color: var(--accent); }
.pick .t { font-family: var(--display); font-weight: 600; font-size: 19px; }
.size { font-family: var(--mono); font-size: 15px; color: var(--accent); font-variant-numeric: tabular-nums; }
.meta ul { margin: 0; padding-left: 18px; color: var(--muted); font-size: 14px; }
.note { font-family: var(--mono); font-size: 12px; color: var(--muted); }
.note a, a { color: var(--accent); }
.item.off { opacity: .55; }
table { border-collapse: collapse; font-size: 14px; }
td, th { border-bottom: 1px solid var(--line); padding: 6px 10px; text-align: left; vertical-align: top; }
th { font-family: var(--mono); font-weight: 500; color: var(--muted); font-size: 12px; text-transform: uppercase; letter-spacing: .05em; }
.scroll { overflow-x: auto; }
.cmp { display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 12px; }
.cmp div { background: var(--panel); border: 1px solid var(--line); border-radius: 8px; padding: 10px 12px; display: flex; flex-direction: column; gap: 6px; }
.cmp b { font-family: var(--display); }
.cmp audio { width: 100%; }
ol.q li { margin-bottom: 6px; max-width: 72ch; }
.tag { font-family: var(--mono); font-size: 12px; color: var(--accent); letter-spacing: .06em; text-transform: uppercase; }
</style>

<main>
<header style="display:flex;flex-direction:column;gap:10px">
  <span class="tag">Tetris Duel · layer 3 · media plan</span>
  <h1>What goes into the 7 MB of flash</h1>
  <p>Every video and picture below was made exactly the way the board will show it: 160 × 120 pixels drawn
  4× bigger, the item's own palette (2 to 256 colours of the board's 4,096), the planned compression, and
  the sound after 4-bit ADPCM encoding and decoding. The game around it is a real screenshot of our design.
  Tick items on or off and the bar shows whether it still fits.</p>
</header>

<div class="bar" aria-live="polite">
  <div class="row"><span class="big" id="tot">0 MB</span><span>of 7.00 MB free in the flash</span><span id="pct"></span></div>
  <div class="meter" id="meter"><i id="fill"></i></div>
</div>

<section id="results">
  <h2>Test 06 on the board: passed</h2>
  <p>ID 01 60 17, the media file found, every picture right, VERIFY 0 bad bytes at 25 MHz (83 ms for 256 KB),
  no sound drop-outs at any speed, sound and picture in sync. The only effect of a slow SPI clock is tearing
  at 3.125 MHz, which the game won't use (it runs at 25 MHz, where a frame loads in 6 ms).</p>
</section>

<section id="sound">
  <h2>Sound quality: same space, better sound</h2>
  <p>Test 06 played 8,000 samples a second, 8 bits each (8 KB per second). The plan: <b>16,000 samples a second
  with 4-bit ADPCM</b> (each sample stored as the <i>change</i> from the last one, in 4 bits, with a step size that
  adapts). Same 8 KB per second, twice the sample rate, much clearer highs. A small decoder in the FPGA turns it
  back into 16-bit samples. The first 30 s of the Teto SV track at each setting:</p>
  <div class="cmp">
    <div><b>8 kHz, 8 bit (test 06)</b><span class="note">8 KB/s</span><audio controls preload="none" src="music_teto_sv_8k_8bit.wav"></audio></div>
    <div><b>11 kHz ADPCM</b><span class="note">5.5 KB/s</span><audio controls preload="none" src="music_teto_sv_11k_adpcm.wav"></audio></div>
    <div><b>16 kHz ADPCM (proposed)</b><span class="note">8 KB/s</span><audio controls preload="none" src="music_teto_sv.wav"></audio></div>
    <div><b>22 kHz ADPCM</b><span class="note">11 KB/s</span><audio controls preload="none" src="music_teto_sv_22k_adpcm.wav"></audio></div>
  </div>
  <p>Song joins (playlist order Teto SV → original → Teto SV …): the last 12 s of one into the first 10 s of the
  next, both ways, with the trimmed silent ends and a short fade.</p>
  <audio controls preload="none" src="music_joins.wav" style="max-width:480px;width:100%"></audio>
</section>
%SECTIONS%

<section id="hardware">
  <h2>What the FPGA needs for this</h2>
  <div class="scroll"><table>
    <tr><th>part</th><th>does</th><th>cost (estimate)</th></tr>
    <tr><td>media player</td><td>flash reader, frame buffer, palette, sound buffer (test 06)</td><td>~700 LUTs, 6 of 10 BRAM tiles</td></tr>
    <tr><td>picture decompression</td><td>delta + run-length: only changed pixels are stored, in runs</td><td>~200 LUTs</td></tr>
    <tr><td>ADPCM decoder</td><td>4-bit sound → 16-bit samples</td><td>~150 LUTs</td></tr>
    <tr><td>two streams</td><td>a long sound track + a short video loop read in turns</td><td>~100 LUTs</td></tr>
    <tr><td>display modes</td><td>background behind the game, full screen, see-through on top, panel picture</td><td>~120 LUTs</td></tr>
    <tr><td>media attack cool-down</td><td>the sender counts down the attack's length + a gap; until then it sends normal attacks only</td><td>~40 LUTs</td></tr>
    <tr><td>sprites</td><td>Jevil (4 frames of 48 × 50, 2×) and faces on the bouncers (32 × 32)</td><td>~200 LUTs, 2 BRAM tiles</td></tr>
    <tr><td>music player</td><td>playlist from flash; stops for media attacks, carries on after</td><td>~80 LUTs (replaces the tune ROM)</td></tr>
  </table></div>
  <p>The chaos game uses 6,200 of 8,000 LUTs (77 %). This adds ~1,500, so the chip would be ~95 % full. That can
  work, but it is the real risk, more than the 7 MB. If it doesn't fit, the order of what to drop:
  sprites first, then the video loops (attacks become sound + a still picture). Some room can be won back by
  removing things the media replaces: the old drawn cat, the Korobeiniki tune ROM, some text layers.</p>
</section>

<section id="questions">
  <h2>Decided (2026-10-20)</h2>
  <ol class="q">
    <li>Music: Teto SV + the original, as a playlist.</li>
    <li>Blocks stay solid during media attacks (hollow looked odd). Media attacks keep their full length, with a
      cool-down on the sender so they never come back to back.</li>
    <li>OIIA: only the psytrance remix, the real video (not a loop), 0:00 to 0:43.75, ending on the fart's tail, just before the first drum (0:43.90).
      Bad Apple at 10 pictures a second. Jevil: 0:20.2 (where the intro ends) to 1:00.5, 0.5 s fade.
      Jevil changes pose 16 times a second and floats at the first speed. Green fringe removed from the jump scares.</li>
    <li>Win / lose: mixed, as shown. The whole rickroll compilation. Jump scares: Foxy and the Puppet.</li>
    <li>No other friends' pictures for now (the four faces stay on the bouncers).</li>
  </ol>
</section>
</main>

<script>
(function () {
  "use strict";
  const FREE = %FREE%;
  const boxes = Array.from(document.querySelectorAll('.pick input'));
  function update() {
    let tot = 0;
    boxes.forEach(b => { if (b.checked) tot += +b.dataset.bytes; b.closest('.item').classList.toggle('off', !b.checked); });
    const pct = 100 * tot / FREE;
    document.getElementById('tot').textContent = (tot / 1048576).toFixed(2) + ' MB';
    document.getElementById('pct').textContent = pct.toFixed(0) + ' %' + (pct > 100 ? ' (too big)' : '');
    document.getElementById('fill').style.width = Math.min(100, pct) + '%';
    document.getElementById('meter').classList.toggle('over', pct > 100);
  }
  boxes.forEach(b => b.addEventListener('change', update));
  update();
})();
</script>
'''

if __name__ == '__main__':
    main()
