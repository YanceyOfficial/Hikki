/** Drawings are only looked at here (`window.hikki.setDrawings`: a phone-sized screen, `DeviceRules.drawingsReadOnly`). */
let readOnly = false

export function setDrawingsReadOnly(on: boolean): void {
  readOnly = on
}

export const drawingsReadOnly = (): boolean => readOnly
