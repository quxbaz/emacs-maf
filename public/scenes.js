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
