// Scenes for showy: each is a list of steps, see showy.js.
// Columns and highlight ranges are as maf places them in a live calc buffer.

export const expand = [
  { stack: ['(x + 1)^2 = 9'] },
  { pause: 900 },
  { point: { level: 1, col: 7 }, highlight: { level: 1, from: 0, to: 9 } },
  { pause: 700 },
  { keys: 'x', command: 'mafcmd-expand' },
  { entry: { level: 1, text: 'x^2 + 2 x + 1 = 9' }, point: { level: 1, col: 9 }, highlight: { level: 1, from: 0, to: 13 } },
]

// A parabola brought into standard form, then plotted: collect the x
// terms, complete the square, move the constant across, simplify the
// other side, factor out its gcd, plot.
export const parabola = [
  { stack: ['x^2 + 2 x + 8 y + 17 = 0'] },
  { pause: 900 },
  { keys: 'j c RET', command: 'mafcmd-collect-terms' },
  { entry: { level: 1, text: 'x^2 + 2 x = -8 y - 17' } },
  { pause: 500 },
  { point: { level: 1, col: 4 }, highlight: { level: 1, from: 0, to: 9 } },
  { pause: 500 },
  { keys: 'k s', command: 'mafcmd-complete-square' },
  { entry: { level: 1, text: '(x + 1)^2 - 1 = -8 y - 17' }, point: { level: 1, col: 10 }, highlight: { level: 1, from: 0, to: 13 } },
  { pause: 500 },
  { point: { level: 1, col: 12 }, highlight: { level: 1, from: 12, to: 13 } },
  { pause: 500 },
  { keys: 'j e', command: 'maf-jump-equals' },
  { entry: { level: 1, text: '(x + 1)^2 = 1 - (17 + 8 y)' }, point: { level: 1, col: 12 }, highlight: { level: 1, from: 12, to: 13 } },
  { pause: 500 },
  { point: { level: 1, col: 14 }, highlight: { level: 1, from: 12, to: 26 } },
  { pause: 500 },
  { keys: 'k k', command: 'mafcmd-esimplify' },
  { entry: { level: 1, text: '(x + 1)^2 = -8 y - 16' }, point: { level: 1, col: 17 }, highlight: { level: 1, from: 12, to: 21 } },
  { pause: 500 },
  { keys: 'l F', command: 'mafcmd-factor-gcd' },
  { entry: { level: 1, text: '(x + 1)^2 = -8 (y + 2)' }, point: { level: 1, col: 14 }, highlight: { level: 1, from: 12, to: 22 } },
  { pause: 700 },
  { keys: 'g l', command: 'maf-plot-embed' },
  { image: 'media/parabola.svg', alt: 'the parabola (x + 1)^2 = -8 (y + 2), vertex at (-1, -2), opening downward' },
]
