// Colour schemes for the features section, to try by eye: the left and
// right arrow keys, anywhere on the page, step through them, and a
// badge in the section's corner names the one in force. A scheme is
// [name, ground, card, accent, text, muted, card text]; the last is for
// a card whose colour the ground's text would not read on, and the
// hover ground and the rules are derived from the card. The pick is kept in localStorage so
// a reload keeps it. Fifty dark schemes, fifty light, fifty neutral,
// fifty of contrast, fifty bold.
export const SCHEMES = [
  ['charcoal gold', '#171410', '#27231e', '#e6b74d', '#f3eee5', '#a79d8e'],
  ['slate', '#141b24', '#1e2937', '#7fbcf0', '#eef2f6', '#9fadbb'],
  ['navy', '#0f1729', '#19243d', '#8ab4ff', '#e9eefc', '#95a3c4'],
  ['ink', '#0d0f14', '#181b23', '#9fb3ff', '#e6e8ef', '#8b90a1'],
  ['graphite', '#1a1a1c', '#26262a', '#c8c8cc', '#f0f0f2', '#9a9aa0'],
  ['midnight teal', '#0e1a1c', '#17282b', '#5fd3c4', '#e6f3f2', '#8fb0ad'],
  ['forest', '#0f1712', '#1a261d', '#8fd39a', '#e9f2ea', '#93a898'],
  ['moss', '#161a12', '#232a1c', '#c2d36a', '#eef1e6', '#a2a98f'],
  ['plum', '#170f1a', '#261a2a', '#d99ae8', '#f2e8f4', '#a894ad'],
  ['wine', '#1b0f12', '#2a1a1f', '#f08a9b', '#f5e9ec', '#ad9399'],
  ['ember', '#1a1210', '#2a1e1a', '#ff9a5c', '#f6ede8', '#ab9a91'],
  ['mocha', '#1c1512', '#2b221e', '#d9a87a', '#f2ebe6', '#a89b92'],
  ['olive', '#15160f', '#22241a', '#b5c46a', '#eef0e4', '#a1a48f'],
  ['ocean', '#0b1620', '#122232', '#59c2ff', '#e5eef7', '#8aa1b5'],
  ['indigo', '#12122a', '#1c1c3e', '#a5a8ff', '#ebebfa', '#9a9bc2'],
  ['nord', '#2e3440', '#3b4252', '#88c0d0', '#eceff4', '#a3adbf'],
  ['dracula', '#1e1f29', '#282a36', '#bd93f9', '#f8f8f2', '#a0a3b5'],
  ['gruvbox', '#1d2021', '#282828', '#fabd2f', '#ebdbb2', '#a89984'],
  ['solarized', '#002b36', '#073642', '#2aa198', '#eee8d5', '#93a1a1'],
  ['monokai', '#1e1f1c', '#272822', '#a6e22e', '#f8f8f2', '#a2a38f'],
  ['one dark', '#21252b', '#282c34', '#61afef', '#dcdfe4', '#9aa2b0'],
  ['tokyo night', '#16161e', '#1a1b26', '#7aa2f7', '#c0caf5', '#8a90b3'],
  ['catppuccin', '#181825', '#1e1e2e', '#cba6f7', '#cdd6f4', '#9399b8'],
  ['everforest', '#232a2e', '#2d353b', '#a7c080', '#d3c6aa', '#9aa79a'],
  ['rose pine', '#191724', '#1f1d2e', '#ebbcba', '#e0def4', '#9c98b8'],
  ['zenburn', '#2f2f2f', '#3f3f3f', '#f0dfaf', '#dcdccc', '#a8a897'],
  ['material', '#1b2226', '#263238', '#80cbc4', '#eeffff', '#98a8b0'],
  ['github dark', '#0d1117', '#161b22', '#58a6ff', '#e6edf3', '#8b949e'],
  ['nightfox', '#131a24', '#192330', '#86abdc', '#cdcecf', '#8f99a8'],
  ['kanagawa', '#16161d', '#1f1f28', '#e6c384', '#dcd7ba', '#9a9584'],
  ['palenight', '#232738', '#292d3e', '#c792ea', '#d6dbea', '#959dba'],
  ['cobalt', '#0d2440', '#193549', '#ffc600', '#ffffff', '#9fb4c8'],
  ['ayu', '#0b0e14', '#11151c', '#e6b450', '#bfbdb6', '#8d9199'],
  ['horizon', '#16161c', '#1c1e26', '#e95678', '#e0e0e0', '#9a9ab0'],
  ['oceanic', '#17262e', '#1b2b34', '#6699cc', '#d8dee9', '#93a1ad'],
  ['spacegray', '#20242b', '#2b303b', '#8fa1b3', '#dfe1e8', '#9ba3b1'],
  ['eighties', '#232323', '#2d2d2d', '#f2777a', '#d3d0c8', '#9d9b96'],
  ['tomorrow', '#1a1b1c', '#1d1f21', '#81a2be', '#c5c8c6', '#8f9294'],
  ['sonokai', '#262a30', '#2c2e34', '#9ed072', '#e2e2e3', '#9ea0a6'],
  ['edge', '#1f2329', '#262b33', '#6cb6eb', '#c5cdd9', '#93a0af'],
  ['iceberg', '#111219', '#161821', '#84a0c6', '#c6c8d1', '#8a8ea3'],
  ['moonlight', '#1b1e2b', '#222436', '#82aaff', '#c8d3f5', '#8f97b6'],
  ['poimandres', '#1b1e28', '#252b37', '#5de4c7', '#e4f0fb', '#8f9cb0'],
  ['andromeda', '#1e2025', '#23262e', '#00e8c6', '#d5ced9', '#9a95a0'],
  ['synthwave', '#1e1530', '#2a1e42', '#ff7edb', '#f4ecff', '#a293bf'],
  ['vesper', '#101010', '#1a1a1a', '#ffc799', '#ffffff', '#8f8f8f'],
  ['aura', '#15141b', '#1d1c25', '#a277ff', '#edecee', '#9a97a6'],
  ['mellow', '#161617', '#1f1f20', '#e2a86f', '#c9c7cd', '#8d8b92'],
  ['deep sea', '#07131d', '#0f1f2c', '#4dd0e1', '#e0f2f7', '#7f9aa8'],
  ['sand dark', '#1b1812', '#2a261d', '#e0c27a', '#f4efe3', '#aa9f88'],
  // Light.
  ['paper', '#f4f4f2', '#ffffff', '#1f5fa8', '#1d1d1d', '#767676'],
  ['snow', '#f6f8fb', '#ffffff', '#2b6cb0', '#1a202c', '#718096'],
  ['linen', '#f7f3ec', '#fffdf9', '#a8541f', '#2b2521', '#8a7f74'],
  ['ivory', '#f9f6ee', '#fffef8', '#8a6d1f', '#2a2620', '#8c8474'],
  ['cream', '#faf4e4', '#fffbf0', '#b8860b', '#2d2a22', '#8f8672'],
  ['sand', '#f2ebdc', '#fbf7ee', '#9c6b2f', '#2f2a22', '#8d8270'],
  ['mist', '#eef1f4', '#f9fafb', '#3b6ea8', '#1f2933', '#7b8794'],
  ['sky', '#e8f1fa', '#ffffff', '#124a72', '#1d1d1d', '#6b7a88'],
  ['aqua', '#e4f4f4', '#f6fcfc', '#0e7c7b', '#1c2a2a', '#6f8887'],
  ['mint', '#e6f5ec', '#f6fcf8', '#1e7a4a', '#1c2a22', '#6f8a7a'],
  ['sage', '#eaf0e6', '#f7faf4', '#4f7a3a', '#242b20', '#7a8873'],
  ['seafoam', '#e3f3ef', '#f4fbf9', '#177a6e', '#1c2926', '#6d8782'],
  ['lavender', '#efecf8', '#faf9fe', '#5b3fa6', '#241f33', '#7f7994'],
  ['lilac', '#f3eef7', '#fcfafe', '#7a3fa0', '#2a2230', '#8a7d95'],
  ['rose', '#f9eef1', '#fefafb', '#a8354f', '#2e2124', '#957d84'],
  ['blush', '#fbeff0', '#fffafa', '#b7455a', '#2f2223', '#98807f'],
  ['peach', '#fdf0e8', '#fffaf7', '#c05a2a', '#2f261f', '#9a8577'],
  ['apricot', '#fcf1e3', '#fffbf4', '#b6651c', '#2e271d', '#988670'],
  ['lemon', '#fbf7dd', '#fffdf0', '#8d7a12', '#2c2a1c', '#908a6a'],
  ['butter', '#fbf5df', '#fffcef', '#a07b17', '#2d2a1f', '#938b70'],
  ['pearl', '#f2f1ee', '#fbfaf8', '#5c6270', '#26262a', '#85868c'],
  ['silver', '#ececec', '#f8f8f8', '#4a5568', '#1f2328', '#7c8288'],
  ['fog', '#eceef0', '#f7f8f9', '#4c5f78', '#242a32', '#7c8794'],
  ['dove', '#f0f0f2', '#fafafb', '#5a5f8a', '#25263a', '#83859a'],
  ['ash', '#efefed', '#f9f9f8', '#616161', '#212121', '#8a8a88'],
  ['birch', '#f5f2ec', '#fdfcf9', '#7c5a34', '#2c2620', '#8d8478'],
  ['oat', '#f4efe6', '#fcfaf5', '#8a6535', '#2d2820', '#8f8677'],
  ['wheat', '#f5edd9', '#fdf9ef', '#9b6a1f', '#2e281d', '#93876f'],
  ['honey', '#fbf1d8', '#fffaeb', '#a8720e', '#2f2818', '#97896a'],
  ['sunrise', '#fdf0e1', '#fff9f2', '#cf5c2a', '#312419', '#9c8676'],
  ['powder', '#e9f0f8', '#f8fafd', '#2f5f9e', '#1e2836', '#75849a'],
  ['ice', '#eaf4fb', '#f8fcff', '#1b6fa8', '#1c2a36', '#71879a'],
  ['glacier', '#e6f0f5', '#f6fafc', '#25708f', '#1d2b33', '#728794'],
  ['arctic', '#eef3f7', '#fafcfd', '#3a6b8f', '#1f2c36', '#7a8b98'],
  ['cloud', '#f1f4f8', '#fbfcfd', '#4a6fa5', '#232b38', '#7f8b9c'],
  ['cotton', '#f7f7fa', '#ffffff', '#6a5acd', '#26243a', '#8a889c'],
  ['porcelain', '#f3f5f5', '#fcfdfd', '#2f6f6f', '#1f2c2c', '#788a8a'],
  ['chalk', '#f6f6f4', '#fefefd', '#3d3d3d', '#1a1a1a', '#808080'],
  ['eggshell', '#f8f5ee', '#fefcf7', '#7a6a3a', '#2b2820', '#8e887a'],
  ['parchment', '#f3ead6', '#fbf6ea', '#8b5a2b', '#2f271d', '#93856f'],
  ['solarized light', '#eee8d5', '#fdf6e3', '#268bd2', '#073642', '#93a1a1'],
  ['gruvbox light', '#f2e5bc', '#fbf1c7', '#b57614', '#3c3836', '#928374'],
  ['nord light', '#e5e9f0', '#eceff4', '#5e81ac', '#2e3440', '#7b8594'],
  ['one light', '#f0f0f0', '#fafafa', '#4078f2', '#383a42', '#8e8e90'],
  ['github light', '#f6f8fa', '#ffffff', '#0969da', '#1f2328', '#656d76'],
  ['tokyo day', '#d5d6db', '#e1e2e7', '#2e7de9', '#3760bf', '#848cb5'],
  ['catppuccin latte', '#e6e9ef', '#eff1f5', '#8839ef', '#4c4f69', '#8c8fa1'],
  ['rose pine dawn', '#faf4ed', '#fffaf3', '#d7827e', '#575279', '#9893a5'],
  ['everforest light', '#efebd4', '#fdf6e3', '#8da101', '#5c6a72', '#939f91'],
  ['ayu light', '#f3f4f5', '#fcfcfc', '#ff9940', '#5c6166', '#8a9199'],
  // Neutral: greys, stones and taupes, mid-toned and low in colour.
  ['stone', '#c9c6c0', '#dedbd5', '#5a4a3a', '#2a2622', '#6d6862'],
  ['taupe', '#b9b0a4', '#cfc7bc', '#5b3f2e', '#2b2420', '#6a6058'],
  ['greige', '#c6c2ba', '#dad6ce', '#4a5a6a', '#26282a', '#6c6a66'],
  ['warm grey', '#bdb9b4', '#d2cec9', '#7a4a3a', '#2a2725', '#6b6764'],
  ['cool grey', '#b8bcc2', '#ced1d6', '#3a5a7a', '#23272c', '#666a70'],
  ['pewter', '#a9adb2', '#c0c3c8', '#2f4f6f', '#1f2327', '#5f6368'],
  ['slate grey', '#9aa3ad', '#b3bac3', '#243d55', '#1c2229', '#565d66'],
  ['ash grey', '#b0b0b0', '#c8c8c8', '#404040', '#1e1e1e', '#626262'],
  ['dust', '#c4bdb3', '#d8d2c9', '#6b4f3a', '#2a2521', '#6e6862'],
  ['clay', '#bfae9e', '#d3c5b7', '#7a3f2a', '#2c231d', '#6f6259'],
  ['putty', '#cfc8ba', '#e0dacf', '#5f5a3a', '#2b2a22', '#6f6c60'],
  ['mushroom', '#b7aca0', '#cbc2b7', '#5c4530', '#2a241f', '#6b6259'],
  ['driftwood', '#aea89c', '#c3bdb2', '#4f4a3e', '#25231e', '#65615a'],
  ['pebble', '#b4b6b3', '#c9cbc8', '#3f5a4a', '#20231f', '#616461'],
  ['flint', '#8e9296', '#a6aaae', '#1f2f3f', '#171a1d', '#4d5155'],
  ['granite', '#8a8a8c', '#a2a2a4', '#2a2a5a', '#161617', '#4a4a4c'],
  ['basalt', '#6f7275', '#87898c', '#e6d6a3', '#f1f1f1', '#c5c7c9'],
  ['charcoal grey', '#5c5c5e', '#727274', '#e9c97a', '#f2f2f2', '#c6c6c8'],
  ['iron', '#66696d', '#7d8085', '#f0c987', '#f3f4f5', '#c9cbce'],
  ['steel', '#6e747a', '#858b91', '#ffd27a', '#f3f5f7', '#cdd1d5'],
  ['gunmetal', '#585e64', '#6e747a', '#f5c869', '#f1f3f5', '#c4c8cc'],
  ['smoke', '#9b9b9b', '#b3b3b3', '#2b2b2b', '#1a1a1a', '#535353'],
  ['cinder', '#7a7674', '#918d8b', '#f2d6a0', '#f4f2f0', '#cdc9c6'],
  ['shale', '#7b8086', '#93989e', '#ffe0a3', '#f5f6f7', '#d0d3d6'],
  ['concrete', '#a8a8a8', '#bfbfbf', '#333333', '#1c1c1c', '#5a5a5a'],
  ['cement', '#b5b3ae', '#cbc9c4', '#4a3f35', '#242220', '#666460'],
  ['plaster', '#d6d2cb', '#e6e3dd', '#6a5545', '#2c2925', '#736f69'],
  ['limestone', '#d1cfc6', '#e2e0d8', '#5a6a4a', '#292a25', '#71716a'],
  ['sandstone', '#c9bca8', '#dcd1c0', '#8a4a2a', '#2e2620', '#736a5e'],
  ['fawn', '#c2b3a0', '#d5c8b8', '#6e3f2a', '#2d241e', '#70655a'],
  ['khaki', '#b9b08f', '#ccc4a8', '#5a4a1a', '#2a281c', '#6d6a55'],
  ['olive grey', '#a5a894', '#bbbead', '#3f4a2a', '#23251c', '#62655a'],
  ['moss grey', '#9aa192', '#b1b7aa', '#2f4a2a', '#1f231c', '#5b6157'],
  ['sea grey', '#9aa6a8', '#b2bcbe', '#1f4a55', '#1c2426', '#5b6467'],
  ['blue grey', '#a2aab4', '#b9c0c9', '#2a4a7a', '#1f242c', '#606770'],
  ['lilac grey', '#aca8b4', '#c2bec9', '#4a2a6a', '#24222a', '#66626c'],
  ['rose grey', '#b4a8a8', '#c9bebe', '#7a2a3a', '#2a2222', '#6c6262'],
  ['mauve grey', '#ada4a9', '#c2babe', '#6a2a4a', '#282224', '#676062'],
  ['bronze grey', '#9c948a', '#b2aaa0', '#5a3a1a', '#231f1b', '#5e5852'],
  ['umber', '#7e746a', '#948a80', '#f3d3a0', '#f5f2ee', '#cfc7be'],
  ['sepia', '#8a7e70', '#a09488', '#ffdca8', '#f6f3ee', '#d3ccc2'],
  ['walnut', '#6e6259', '#84786f', '#f0c890', '#f4f1ed', '#c9c1b9'],
  ['bark', '#6a625a', '#807870', '#f2cd8c', '#f3f0ec', '#c7c0b8'],
  ['ashwood', '#a09a90', '#b6b0a6', '#4a3a2a', '#24211d', '#615c55'],
  ['heather', '#9b98a4', '#b1aeb9', '#3a2a5a', '#211f27', '#5c5964'],
  ['thistle', '#a8a4ae', '#bebac3', '#5a2a5a', '#25222a', '#655f68'],
  ['oyster', '#c8c4bd', '#dbd8d1', '#4a5a5a', '#262928', '#6d6c68'],
  ['mineral', '#a3a8a6', '#babfbd', '#2a4a4a', '#1f2424', '#5f6463'],
  ['graphite grey', '#7f8184', '#96989b', '#f1d089', '#f3f4f5', '#cdced0'],
  ['slate stone', '#8c9096', '#a3a7ad', '#ffd58c', '#f4f5f6', '#d0d3d7'],
  // Contrast: the cards do not match the ground. A seventh entry is
  // the text colour on the cards, where the ground's would not read.
  ['ink & paper', '#111111', '#ffffff', '#c62828', '#f2f2f2', '#9a9a9a', '#141414'],
  ['paper & ink', '#f4f4f2', '#1b1b1b', '#ffb74d', '#141414', '#767676', '#f0f0f0'],
  ['navy & cream', '#0f1f3d', '#fbf5e6', '#b8860b', '#eef2fa', '#9fb0cc', '#2a2418'],
  ['cream & navy', '#faf4e4', '#12304f', '#ffd166', '#2d2a22', '#8f8672', '#eef3fb'],
  ['forest & ivory', '#122a1c', '#f9f6ec', '#1e7a4a', '#e9f2ea', '#93a898', '#1f2a20'],
  ['ivory & forest', '#f8f5ec', '#183d2a', '#a7e0b8', '#26301f', '#8c8e74', '#eef6ef'],
  ['wine & linen', '#3a1220', '#f7f2ea', '#a8354f', '#f5e9ec', '#b8969e', '#2b2222'],
  ['linen & wine', '#f5efe6', '#4a1a2a', '#f4a7b9', '#2e2424', '#8e7f7c', '#f8ecef'],
  ['ochre & white', '#b8860b', '#ffffff', '#7a5200', '#fff8e6', '#f2dfa8', '#1d1d1d'],
  ['white & ochre', '#ffffff', '#b8860b', '#3a2a00', '#1d1d1d', '#777777', '#fff9e8'],
  ['teal & sand', '#0e5c5a', '#f3e9d2', '#0e5c5a', '#e6f3f2', '#a9d0ce', '#2a2620'],
  ['sand & teal', '#f2e8d5', '#0f5e5b', '#9ee8e2', '#2c2822', '#8c8470', '#e8f6f5'],
  ['cobalt & white', '#0d2f6b', '#ffffff', '#0d2f6b', '#eaf0fb', '#9fb4d8', '#1d1d1d'],
  ['white & cobalt', '#ffffff', '#123c8a', '#ffd166', '#1d1d1d', '#777777', '#eef3fc'],
  ['plum & peach', '#3b1a3e', '#fde8d8', '#a0405a', '#f2e8f4', '#b89bbd', '#3a2222'],
  ['peach & plum', '#fdece0', '#4a1f4d', '#ffb59a', '#2f261f', '#9a8577', '#f6e8f7'],
  ['charcoal & mint', '#1e1e1e', '#dff5e8', '#1e7a4a', '#f0f0f0', '#9a9a9a', '#16261c'],
  ['mint & charcoal', '#e6f5ec', '#232323', '#8fd39a', '#1c2a22', '#6f8a7a', '#f0f0f0'],
  ['black & yellow', '#000000', '#ffd400', '#000000', '#ffffff', '#a0a0a0', '#1a1400'],
  ['yellow & black', '#ffd400', '#111111', '#ffd400', '#1a1400', '#6b5a00', '#f4f4f4'],
  ['brick & white', '#8b2f24', '#ffffff', '#8b2f24', '#fbeeec', '#e0b3ad', '#1d1d1d'],
  ['white & brick', '#ffffff', '#9a3a2e', '#ffd9a8', '#1d1d1d', '#777777', '#fff1ee'],
  ['midnight & rose', '#0b1020', '#fbe4ea', '#b0345a', '#e9eefc', '#95a3c4', '#3a1a24'],
  ['rose & midnight', '#fbe9ee', '#111a33', '#f5a3b8', '#2e2124', '#957d84', '#eef1fb'],
  ['olive & white', '#4a5a2a', '#ffffff', '#4a5a2a', '#f1f4e8', '#b9c4a0', '#1d1d1d'],
  ['white & olive', '#fbfbf8', '#55662f', '#e2f0a8', '#1f2418', '#7a8060', '#f4f7ec'],
  ['slate & lemon', '#2f3a48', '#fff7cc', '#2f3a48', '#e8edf3', '#a3b0c2', '#2a2a1c'],
  ['lemon & slate', '#fdf6d0', '#334152', '#ffe89a', '#2c2a1c', '#908a6a', '#eef2f7'],
  ['espresso & milk', '#2c1a12', '#fbf3ea', '#8a4a1f', '#f4ebe4', '#b39a8a', '#2e2118'],
  ['milk & espresso', '#f9f2ea', '#3a2318', '#f5c29a', '#2d221b', '#8e8074', '#f8efe8'],
  ['indigo & apricot', '#1d1b4a', '#fdebd3', '#b3521a', '#ebebfa', '#9a9bc2', '#3a2a18'],
  ['apricot & indigo', '#fcefdc', '#23215a', '#ffc98a', '#2e271d', '#988670', '#eeedf8'],
  ['pine & blush', '#1c3a30', '#fbeaea', '#9a3a4a', '#e8f0ec', '#98b0a6', '#3a2222'],
  ['blush & pine', '#fbeef0', '#204236', '#a8e6c8', '#2f2223', '#98807f', '#e9f5ef'],
  ['grey & gold', '#3a3a3a', '#f3e2a8', '#6b4f00', '#f0f0f0', '#a8a8a8', '#2a2410'],
  ['gold & grey', '#f2dfa0', '#3a3a3a', '#ffd97a', '#2a2410', '#7a6c3a', '#f0f0f0'],
  ['sea & shell', '#0f3b52', '#fbf1e8', '#1b6fa8', '#e6eef5', '#9bb7c8', '#2a2420'],
  ['shell & sea', '#fbf2ea', '#12405a', '#9fd9ff', '#2f261f', '#9a8577', '#eaf3f9'],
  ['moss & chalk', '#3b4a2a', '#f7f7f2', '#3b4a2a', '#eef1e6', '#aab59a', '#1f2418'],
  ['chalk & moss', '#f6f6f2', '#42532e', '#d4e69a', '#1f2418', '#7f8474', '#f1f6e8'],
  ['violet & ivory', '#3a2260', '#fbf8ef', '#5b3fa6', '#efe8fa', '#b5a6d6', '#241f33'],
  ['ivory & violet', '#faf7ee', '#3d2669', '#d9c6ff', '#241f33', '#8a8376', '#f3eefb'],
  ['rust & sky', '#8a3a1a', '#e8f1fa', '#8a3a1a', '#fbeee8', '#e0b8a8', '#1d2a36'],
  ['sky & rust', '#e6f0fa', '#8f3d1d', '#ffcfa8', '#1d2a36', '#6b7a88', '#fff0e8'],
  ['ash & coral', '#2b2b2b', '#ffd9cc', '#b03a2a', '#f0f0f0', '#9a9a9a', '#3a1f18'],
  ['coral & ash', '#ffe1d6', '#2e2e2e', '#ff9a7a', '#3a1f18', '#9a7268', '#f2f2f2'],
  ['deep sea & sun', '#07131d', '#fff1b8', '#8a6a00', '#e0f2f7', '#7f9aa8', '#2a2410'],
  ['sun & deep sea', '#fff3c4', '#0b1c2a', '#ffe08a', '#2a2410', '#8a7a4a', '#e6f0f6'],
  ['stone & sky', '#8c8780', '#e8f1fa', '#124a72', '#f4f2ef', '#d8d3cc', '#1d2a36'],
  ['sky & stone', '#e8f1fa', '#6f6a63', '#f2dfa8', '#1d2a36', '#6b7a88', '#f4f2ef'],
  // Bold: a saturated ground, light cards, the ground's hue as the
  // card accent.
  ['crimson', '#b3122e', '#fff5f6', '#b3122e', '#fff0f2', '#f2b3bd', '#2a1216'],
  ['scarlet', '#d7263d', '#fff6f4', '#c21f34', '#fff1f0', '#f5b9bf', '#2c1416'],
  ['vermilion', '#e34a1f', '#fff7f2', '#c53d15', '#fff2ec', '#f7c4b3', '#2e1a12'],
  ['tangerine', '#f27d16', '#fff9f0', '#c25f05', '#fff5e8', '#fbd3a6', '#2e1f0e'],
  ['amber', '#f0a500', '#fffbe8', '#9a6a00', '#2b1f00', '#7a5a10', '#2a2000'],
  ['marigold', '#e8b41a', '#fffbe6', '#8a6600', '#2a2000', '#7a6210', '#2a2200'],
  ['mustard', '#c9a227', '#fffbea', '#7a5f10', '#2a2200', '#6e5c1e', '#2a2200'],
  ['chartreuse', '#9acd32', '#fbfff0', '#4f7a00', '#1e2a08', '#4f6a1a', '#1e2a08'],
  ['lime', '#6fbf1f', '#f7fff0', '#3e7a0a', '#f3ffe8', '#c7ecaa', '#1a2a0e'],
  ['kelly', '#2e8b3d', '#f4fdf5', '#22702f', '#eefbf0', '#a9dfb2', '#12261a'],
  ['emerald', '#0f8a5f', '#f0fbf6', '#0b6b49', '#e8f9f1', '#9fdcc4', '#0f2a20'],
  ['jade', '#1a9c85', '#effcf9', '#11776a', '#e8faf6', '#a1dcd2', '#0f2a26'],
  ['turquoise', '#14b3c1', '#effcfd', '#0b7e8a', '#0d2a2e', '#0f5d66', '#0d2a2e'],
  ['cyan', '#0ab5d6', '#f0fbfe', '#0680a0', '#0b2a33', '#0f6070', '#0b2a33'],
  ['cerulean', '#0a7bc4', '#f1f8fe', '#0a6bab', '#eaf4fd', '#a4cdee', '#0f2438'],
  ['azure', '#1e6fe0', '#f2f7ff', '#1a5fc0', '#ecf3ff', '#a9c6f5', '#0f2040'],
  ['royal blue', '#2540c9', '#f3f5ff', '#1f36ad', '#eef1ff', '#aab5f0', '#12184a'],
  ['ultramarine', '#1b2fa8', '#f2f4fe', '#182a94', '#ecefff', '#a7b0e8', '#12184a'],
  ['sapphire', '#0e3d91', '#f1f5fd', '#0e3d91', '#ebf1fc', '#a0b8e0', '#101f3d'],
  ['indigo bold', '#3f2b96', '#f5f2fe', '#3a2788', '#f0ecff', '#bfb2ea', '#1e1640'],
  ['violet bold', '#6a2fc1', '#f8f3ff', '#5f29ad', '#f3ecff', '#cbb6ee', '#2a1a4a'],
  ['purple', '#7b2d8e', '#fbf3fd', '#6f2880', '#f8ecfb', '#d7b3de', '#2e1533'],
  ['magenta', '#c2188a', '#fff2fa', '#a8137a', '#fff0f8', '#f0b0d8', '#3a1030'],
  ['fuchsia', '#d63384', '#fff3f9', '#b82a70', '#fff0f6', '#f3b8d4', '#3a1225'],
  ['hot pink', '#e8399b', '#fff4fa', '#c42f83', '#fff1f8', '#f7bedb', '#3a1428'],
  ['raspberry', '#a5194b', '#fff3f6', '#a5194b', '#ffeef2', '#e9a8bb', '#301018'],
  ['cherry', '#9b1c31', '#fff4f5', '#9b1c31', '#ffeff1', '#e6a6ae', '#2c1014'],
  ['burgundy', '#6e1423', '#fdf4f5', '#6e1423', '#fbecee', '#d9a3aa', '#2a1014'],
  ['maroon', '#7a1f2b', '#fdf5f5', '#7a1f2b', '#fbeeee', '#dba9ad', '#2a1214'],
  ['rust bold', '#b7410e', '#fff7f2', '#a3390b', '#fff2ea', '#f0c0a6', '#2e1a10'],
  ['copper', '#b86b2a', '#fff8f1', '#9c5a20', '#fff3e8', '#efc9a8', '#2e1e12'],
  ['bronze', '#9c6b1e', '#fff9ee', '#7e5514', '#fff5e4', '#e8caa0', '#2c2010'],
  ['ochre bold', '#c9862b', '#fffaf0', '#9c6718', '#fff6e6', '#f2d4a8', '#2e2010'],
  ['olive bold', '#6b7a1c', '#fbfdf0', '#556214', '#f6fbe8', '#cfdba0', '#22280a'],
  ['moss bold', '#4f7a2a', '#f6fcf1', '#3f6420', '#f1fae9', '#bfdba8', '#1a2a10'],
  ['pine bold', '#1f5e3a', '#f1faf4', '#1f5e3a', '#eaf7ee', '#a4d2b6', '#10281a'],
  ['teal bold', '#0b6e6e', '#effafa', '#0b6e6e', '#e8f7f7', '#9fd4d4', '#0e2626'],
  ['petrol', '#0b4f6c', '#eff8fc', '#0b4f6c', '#e9f4fa', '#9fc6d8', '#0e2430'],
  ['prussian', '#0b3d5c', '#eef6fb', '#0b3d5c', '#e8f2f8', '#9cbdd2', '#0e2130'],
  ['navy bold', '#0d2b6b', '#f1f5fd', '#0d2b6b', '#ebf1fb', '#a2b5dc', '#101c3a'],
  ['midnight bold', '#171a4a', '#f3f3fc', '#2b2f8a', '#eeeefa', '#aaadd8', '#15173a'],
  ['aubergine', '#4a1a4f', '#faf3fb', '#4a1a4f', '#f7ecf9', '#cfa8d4', '#2a1030'],
  ['grape', '#5e2b8a', '#f8f3fd', '#5e2b8a', '#f4ecfb', '#c6aee0', '#28143a'],
  ['orchid', '#a83aa0', '#fdf3fc', '#8e2f88', '#fbecfa', '#e6b4e2', '#301030'],
  ['coral bold', '#ff6f59', '#fff7f5', '#c94a36', '#fff3f0', '#ffcfc6', '#33160f'],
  ['salmon', '#f08a7a', '#fff8f6', '#b8503f', '#2e1610', '#8a4030', '#2e1610'],
  ['peach bold', '#f5a67a', '#fffaf6', '#b55a2a', '#2e1a10', '#8a4a20', '#2e1a10'],
  ['gold bold', '#d4a017', '#fffbea', '#8a6600', '#2a2000', '#6e5610', '#2a2000'],
  ['brass', '#b5952a', '#fffbec', '#7a6414', '#2a2200', '#6a5a1a', '#2a2200'],
  ['slate bold', '#3d5a80', '#f2f6fb', '#3d5a80', '#ecf2f9', '#aabfd8', '#14202e'],
]

const KEY = 'maf-scheme'

// A hex colour mixed toward `to` (0 black, 255 white) by `t` (0..1).
function mix(hex, to, t) {
  const n = parseInt(hex.slice(1), 16)
  const c = [n >> 16 & 255, n >> 8 & 255, n & 255].map(v => Math.round(v + (to - v) * t))
  return '#' + c.map(v => v.toString(16).padStart(2, '0')).join('')
}

// Whether a hex colour reads as light.
const light = hex => {
  const n = parseInt(hex.slice(1), 16)
  return (.299 * (n >> 16 & 255) + .587 * (n >> 8 & 255) + .114 * (n & 255)) > 140
}

export function apply(section, badge, i) {
  const [name, ground, card, accent, fg, muted, cardFg] = SCHEMES[i]
  const s = section.style
  if (cardFg) s.setProperty('--card-fg', cardFg); else s.removeProperty('--card-fg')
  s.setProperty('--ground', ground)
  s.setProperty('--bg', card)
  s.setProperty('--link-2', accent)
  s.setProperty('--fg', fg)
  s.setProperty('--muted', muted)
  // The hover ground and the rules step away from the card: toward
  // white on a dark card, toward black on a light one.
  const to = light(card) ? 0 : 255
  s.setProperty('--panel-2', mix(card, to, light(card) ? .05 : .07))
  s.setProperty('--grid-line', mix(card, to, light(card) ? .14 : .18))
  if (badge) badge.textContent = `${i + 1}/${SCHEMES.length} ${name}`
}

export function mount(root = document) {
  const section = root.querySelector('.examples')
  if (!section) return
  const badge = document.createElement('div')
  badge.className = 'scheme-badge'
  section.append(badge)
  let i = 0
  try { i = Math.min(SCHEMES.length - 1, Math.max(0, parseInt(localStorage.getItem(KEY)) || 0)) } catch {}
  const go = (n) => {
    i = (n + SCHEMES.length) % SCHEMES.length
    apply(section, badge, i)
    try { localStorage.setItem(KEY, i) } catch {}
  }
  addEventListener('keydown', (ev) => {
    if (ev.key !== 'ArrowLeft' && ev.key !== 'ArrowRight') return
    if (ev.target instanceof Element && ev.target.matches('input, textarea, select')) return
    ev.preventDefault()
    go(i + (ev.key === 'ArrowRight' ? 1 : -1))
  })
  go(i)
}
