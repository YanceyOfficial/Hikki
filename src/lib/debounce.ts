export function debounce<A extends unknown[]>(
  fn: (...args: A) => void,
  ms: number
) {
  let timer: ReturnType<typeof setTimeout> | undefined
  let pending: A | undefined
  const run = () => {
    if (!pending) return
    const args = pending
    pending = undefined
    fn(...args)
  }
  const debounced = (...args: A) => {
    pending = args
    clearTimeout(timer)
    timer = setTimeout(run, ms)
  }
  debounced.flush = () => {
    clearTimeout(timer)
    run()
  }
  return debounced
}
