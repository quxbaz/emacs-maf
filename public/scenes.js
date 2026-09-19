// Scenes for showy: each is a list of steps, see showy.js.
// Columns and highlight ranges are as maf places them in a live calc buffer.

// The same key on the same entry, twice: where point stands decides
// what it acts on. On the + only the side under point is squared; on
// the = the whole equation is the target and both sides are. Entries,
// ranges and results are as a live calc buffer gives them.
export const square = [
  { stack: ['y = x + 1'] },
  { pause: 900 },
  { point: { level: 1, col: 6 }, highlight: { level: 1, from: 4, to: 9 } },
  { pause: 700 },
  { keys: 'W', label: 'square', command: 'mafcmd-sqr' },
  { entry: { level: 1, text: 'y = (x + 1)^2' }, point: { level: 1, col: 11 }, highlight: { level: 1, from: 4, to: 13 } },
]

export const squareWhole = [
  { stack: ['y = x + 1'] },
  { pause: 900 },
  { point: { level: 1, col: 2 }, highlight: { level: 1, from: 0, to: 9 } },
  { pause: 700 },
  { keys: 'W', label: 'square', command: 'mafcmd-sqr' },
  { entry: { level: 1, text: 'y^2 = (x + 1)^2' }, point: { level: 1, col: 4 }, highlight: { level: 1, from: 0, to: 15 } },
]

// The expand pair, kept for the scene reference in demo.html.
export const expand = [
  { stack: ['(x + 1)^2 = (y + 2)^2'] },
  { pause: 900 },
  { point: { level: 1, col: 7 }, highlight: { level: 1, from: 0, to: 9 } },
  { pause: 700 },
  { keys: 'x', command: 'mafcmd-expand' },
  { entry: { level: 1, text: 'x^2 + 2 x + 1 = (y + 2)^2' }, point: { level: 1, col: 7 }, highlight: { level: 1, from: 0, to: 13 } },
]

// A parabola brought into standard form, then plotted: collect the x
// terms, complete the square, move the constant across, simplify the
// other side, factor out its gcd, plot.
export const parabola = [
  { stack: ['x^2 + 2 x + 8 y + 17 = 0'], note: 'A parabola in general form. Standard form, (x \u2212 h)\u00b2 = 4p (y \u2212 k), shows the vertex (h, k) and which way it opens.' },
  { pause: 900 },
  { keys: 'j c RET', command: 'mafcmd-collect-terms', note: 'Gather the x terms on the left; everything else goes to the right.' },
  { entry: { level: 1, text: 'x^2 + 2 x = -8 y - 17' } },
  { pause: 500 },
  { point: { level: 1, col: 4 }, highlight: { level: 1, from: 0, to: 9 }, note: 'The x terms, x\u00b2 + 2x, are almost a perfect square.' },
  { pause: 500 },
  { keys: 'k s', command: 'mafcmd-complete-square', note: 'Complete the square: x\u00b2 + 2x = (x + 1)\u00b2 \u2212 1.' },
  { entry: { level: 1, text: '(x + 1)^2 - 1 = -8 y - 17' }, point: { level: 1, col: 10 }, highlight: { level: 1, from: 0, to: 13 } },
  { pause: 500 },
  { point: { level: 1, col: 12 }, highlight: { level: 1, from: 12, to: 13 }, note: 'The \u22121 left over does not belong with the square.' },
  { pause: 500 },
  { keys: 'j e', command: 'maf-jump-equals', note: 'Move it across: subtracting \u22121 from both sides adds 1 on the right.' },
  { entry: { level: 1, text: '(x + 1)^2 = 1 - (17 + 8 y)' }, point: { level: 1, col: 12 }, highlight: { level: 1, from: 12, to: 13 } },
  { pause: 500 },
  { point: { level: 1, col: 14 }, highlight: { level: 1, from: 12, to: 26 }, note: 'The right side, 1 \u2212 (17 + 8y), wants tidying.' },
  { pause: 500 },
  { keys: 'k k', command: 'mafcmd-esimplify', note: 'Simplify: 1 \u2212 17 \u2212 8y = \u22128y \u2212 16.' },
  { entry: { level: 1, text: '(x + 1)^2 = -8 y - 16' }, point: { level: 1, col: 17 }, highlight: { level: 1, from: 12, to: 21 } },
  { pause: 500 },
  { keys: 'l F', command: 'mafcmd-factor-gcd', note: 'Factor out \u22128: now 4p = \u22128, so p = \u22122, and the vertex is (\u22121, \u22122).' },
  { entry: { level: 1, text: '(x + 1)^2 = -8 (y + 2)' }, point: { level: 1, col: 14 }, highlight: { level: 1, from: 12, to: 22 } },
  { pause: 700 },
  { keys: 'g l', command: 'maf-plot-embed', note: 'p is negative, so the parabola opens downward from its vertex at (\u22121, \u22122).' },
  { image: 'media/parabola.svg', alt: 'the parabola (x + 1)^2 = -8 (y + 2), vertex at (-1, -2), opening downward' },
]


// The hypotenuse of a right triangle from its legs: the theorem from
// the formula library, the legs as an assignment, the equation solved.
export const hypotenuse = [
  { stack: [], note: 'A right triangle with legs 3 and 4. How long is the hypotenuse?' },
  { pause: 900 },
  { keys: 's o RET', command: 'maf-formulas', note: 'The Pythagorean theorem: the squares of the legs add up to the square of the hypotenuse.' },
  { push: 'a^2 + b^2 = c^2' },
  { pause: 700 },
  { keys: "'", command: 'calc-algebraic-entry', note: 'The legs: a = 3 and b = 4, typed as one assignment.' },
  { push: '[a = 3, b = 4]' },
  { pause: 700 },
  { keys: 'M-RET', command: 'mafcmd-let', note: 'Substitute them into the theorem: 3\u00b2 + 4\u00b2 = 9 + 16 = 25, so 25 = c\u00b2.' },
  { pop: 1, entry: { level: 1, text: '25 = c^2' } },
  { pause: 700 },
  { keys: 'i c RET', command: 'mafcmd-solve-for', note: 'Solve for c: the square root of 25 is 5. The hypotenuse is 5.' },
  { entry: { level: 1, text: 'c = 5' } },
]

// Scenes for the feature stages: short, one idea each.

// The highlight follows point: each stop shows what a command would act on.
export const highlight = [
  { stack: ['(x + 1)^2 = -8 (y + 2)'] },
  { pause: 600 },
  { point: { level: 1, col: 3 }, highlight: { level: 1, from: 1, to: 6 } },
  { pause: 900 },
  { point: { level: 1, col: 7 }, highlight: { level: 1, from: 0, to: 9 } },
  { pause: 900 },
  { point: { level: 1, col: 18 }, highlight: { level: 1, from: 16, to: 21 } },
  { pause: 900 },
  { point: { level: 1, col: 10 }, highlight: { level: 1, from: 0, to: 22 } },
  { pause: 1200 },
]

// The stack edited in place: SPC, type at point, RET.
export const edit = [
  { stack: ['x + 1'] },
  { pause: 600 },
  { point: { level: 1, col: 5 } },
  { keys: 'SPC', command: 'maf-edit' },
  { insert: ' + y^2' },
  { pause: 500 },
  { keys: 'RET', command: 'maf-edit-commit' },
  { entry: { level: 1, text: 'x + 1 + y^2' } },
]

// Single keys for the usual work: square, expand, undo.
export const bindings = [
  { stack: ['x + 1'] },
  { pause: 600 },
  { point: { level: 1, col: 2 }, highlight: { level: 1, from: 0, to: 5 } },
  { keys: 'W', command: 'mafcmd-sqr' },
  { entry: { level: 1, text: '(x + 1)^2' }, point: { level: 1, col: 7 }, highlight: { level: 1, from: 0, to: 9 } },
  { pause: 500 },
  { keys: 'x', command: 'mafcmd-expand' },
  { entry: { level: 1, text: 'x^2 + 2 x + 1' }, point: { level: 1, col: 4 }, highlight: { level: 1, from: 0, to: 13 } },
  { pause: 500 },
  { keys: 'U', command: 'maf-undo' },
  { entry: { level: 1, text: '(x + 1)^2' }, point: { level: 1, col: 7 }, highlight: { level: 1, from: 0, to: 9 } },
]

// A polynomial put in descending order by simplification.
export const rewrite = [
  { stack: ['1 + x + x^2'] },
  { keys: 'k k', command: 'mafcmd-esimplify' },
  { entry: { level: 1, text: 'x^2 + x + 1' } },
]
