export type ActivityLevel = 'none' | 'low' | 'medium' | 'high'

export function bucketActivityLevel(count: number): ActivityLevel {
  if (count === 0) return 'none'
  if (count <= 2) return 'low'
  if (count <= 5) return 'medium'
  return 'high'
}
