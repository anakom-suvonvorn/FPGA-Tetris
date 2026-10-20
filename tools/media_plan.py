"""
media_plan.py - WHAT media goes into the game, and HOW each piece is stored.

This is the one list everybody edits. tools/media_lab.py turns it into
renders (exactly what the board will show / play) and a size budget;
later tools/make_media.py builds the flash file from the same list.

Every item:
  id        short name (also the render file name)
  group     music | attack | win | lose | sprite
  title     what we call it
  src       the source file (in media/)
  start,dur which part of the source to use, in seconds (dur None = to the end)
  kind      sound | av (picture + sound) | image | sprite
  mode      how it is shown (see media_lab.py / the plan page):
              bg     whole-screen background behind the game, tetris blocks
                     drawn hollow so you see through them
              full   whole screen, covers the game (only the result text on top)
              over   whole screen ON TOP of the game, green-screen colour
                     made see-through (jump scares)
              panel  a small picture in the right panel (2x size)
  bpp       bits per pixel: 1 (2 colours), 2 (4), 4 (16), 8 (256)
  fps       pictures per second
  rate      sound samples per second (the sound is 4-bit ADPCM: rate / 2 bytes a second)
  loop      (start, dur) of a short video piece that repeats while the sound
            plays (saves a lot of space); None = the video runs with the sound
  audio     another file for the sound (default: src)
  key       'green' = green-screen colour becomes see-through
  fade      seconds of fade-out at the end of the sound
  dim       background brightness behind the game (bg mode): 0.75 or 0.5
  keep      True = in the proposed set, False = rendered for comparison only
"""

M = 'media/'

PLAN = [
    # ------------------------------------------------------------------ music
    dict(id='music_teto_sv', group='music', title='Tetris (Teto SV)', kind='sound', keep=True,
         src=M + 'music/テトリス 重音テトSV - Hiiragi Magnetite (192k).mp3', start=0, dur=141.2,
         rate=16000, fade=2.0),
    dict(id='music_original', group='music', title='Tetris (original)', kind='sound', keep=True,
         src=M + 'music/Original Tetris theme (Tetris Soundtrack) - Marcel S (192k).mp3', start=0, dur=None,
         rate=16000, fade=1.5),
    dict(id='music_eurobeat', group='music', title='TETORIS Eurobeat Remix', kind='sound', keep=False,
         src=M + 'music/TETORIS Eurobeat Remix - Hiiragi Magnetite & Kasane Teto - IMOJIST (192k).mp3',
         start=0.9, dur=205.8, rate=16000, fade=2.0),
    dict(id='music_metal', group='music', title='Tetris (metal)', kind='sound', keep=False,
         src=M + 'music/Tetris Metal Version - Release - Topic (192k).mp3', start=0, dur=131.0,
         rate=16000, fade=2.0),

    # ------------------------------------------------------------------ attacks (background video + its sound)
    dict(id='atk_badapple', group='attack', title='Bad Apple!!', kind='av', mode='bg', keep=True,
         src=M + 'effects/【東方】Bad Apple!! ＰＶ【影絵】 - kasidid2 (360p).mp4', start=0, dur=84.2,
         bpp=1, fps=10, rate=16000, loop=None, fade=0.4, dim=0.5),
    dict(id='atk_oiia_psy', group='attack', title='OIIA OIIA (psytrance remix)', kind='av', mode='bg', keep=True,
         src=M + 'effects/Oiiai Cat Psytrance Remix - 鱼头VishKop (1080p).mp4', start=0, dur=43.75,
         bpp=4, fps=10, rate=16000, loop=None, fade=0.2),
    dict(id='atk_jevil', group='attack', title='JEVIL: THE WORLD REVOLVING', kind='av', mode='bg', keep=True,
         src=M + 'effects/jevil_background.mp4', start=20.2, dur=40.3,
         audio=M + 'effects/THE WORLD REVOLVING - Toby Fox (128k).mp3',
         bpp=2, fps=10, rate=16000, loop=(0, 3.4), fade=0.5),

    # ------------------------------------------------------------------ sprites (small pictures drawn on top)
    dict(id='spr_jevil', group='sprite', title='Jevil (floats over the whole screen)', kind='sprite', keep=True,
         src=M + 'effects/jevil-deltarune.gif', size=(48, 50), bpp=4, scale=2),
    dict(id='spr_faces', group='sprite', title='Friends on the bouncers', kind='sprite', keep=True,
         src=[M + 'effects/1535676718092779520.webp', M + 'effects/1535681762867417138.webp',
              M + 'effects/1535681813345996902.webp', M + 'effects/1537689240840962108.webp'],
         size=(32, 32), bpp=8, scale=1),

    # ------------------------------------------------------------------ when you lose (one picked at random)
    dict(id='lose_rickroll', group='lose', title='10 rickrolls', kind='av', mode='full', keep=True,
         src=M + 'lose/10 rickrolls 1 video - Jacob Ramielle (1080p).mp4', start=0, dur=None,
         bpp=4, fps=10, rate=16000, loop=None, fade=0.5),
    dict(id='lose_foxy', group='lose', title='Foxy jump scare', kind='av', mode='over', keep=True,
         src=M + 'lose/Fnaf 2 Foxy Jumpscare Green Screen - Eustass Kidd (720p).mp4', start=0, dur=None,
         bpp=8, fps=15, rate=16000, loop=None, key='green', fade=0.2),
    dict(id='lose_puppet', group='lose', title='Puppet jump scare', kind='av', mode='over', keep=True,
         src=M + 'lose/FNaF 2 Jumpscares Green Screened - Jared Dinosaur (480p).mp4', start=1.0, dur=1.0,
         bpp=8, fps=15, rate=16000, loop=None, key='green', fade=0.2),
    dict(id='lose_loss0', group='lose', title='Loss (1)', kind='image', mode='full', keep=True,
         src=M + 'lose/loss0.jpg', bpp=4),
    dict(id='lose_loss1', group='lose', title='Loss (2)', kind='image', mode='full', keep=True,
         src=M + 'lose/loss1.webp', bpp=4),
    dict(id='lose_loss2', group='lose', title='Loss (3)', kind='image', mode='full', keep=True,
         src=M + 'lose/loss2.jpg', bpp=4),

    # ------------------------------------------------------------------ when you win (one picked at random)
    dict(id='win_yippee', group='win', title='Yippee cat', kind='av', mode='full', keep=True,
         src=M + 'win/yippee cat 😁 - chefman (1080p).mp4', start=0, dur=None,
         bpp=8, fps=10, rate=16000, loop=None, fade=0.3),
    dict(id='win_diabeetus', group='win', title='Diabeetus wishes u greatness', kind='image', mode='panel', keep=True,
         src=M + 'win/diabeetus wishes u greatness.png', bpp=8),
    dict(id='win_miku', group='win', title='Miku approves', kind='image', mode='panel', keep=True,
         src=M + 'win/images.jpg', bpp=8),
    dict(id='win_teto', group='win', title='Teto approves', kind='image', mode='panel', keep=True,
         src=M + 'win/does-anyone-have-any-teto-reaction-image-especially-the-v0-q1p6f8mjb8uf1.webp', bpp=8),
]
