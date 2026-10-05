export function levelTaskProgress(current: number, target: number, full: boolean = false): number {
  if (full) { return 100 }
  if (!Number.isFinite(current) || !Number.isFinite(target)) { return 0 }
  if (target <= 0) { return 100 }
  return Math.max(0, Math.min(100, current * 100 / target))
}
