// Screenshot links still open their images when JavaScript is unavailable.
export function mount() {
  const dialog = document.querySelector('.feature-viewer')
  if (!dialog || typeof dialog.showModal !== 'function') return
  const title = dialog.querySelector('h2')
  const image = dialog.querySelector('img')
  const original = dialog.querySelector('.original')

  for (const link of document.querySelectorAll('.feature-shot')) {
    link.addEventListener('click', event => {
      if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
      event.preventDefault()
      const thumbnail = link.querySelector('img')
      title.textContent = link.closest('section').querySelector('h3').textContent
      image.src = link.href
      image.alt = thumbnail.alt
      original.href = link.href
      dialog.showModal()
    })
  }

  dialog.addEventListener('click', event => {
    if (event.target !== dialog) return
    const rect = dialog.getBoundingClientRect()
    if (event.clientX < rect.left || event.clientX > rect.right ||
        event.clientY < rect.top || event.clientY > rect.bottom) dialog.close()
  })
}
