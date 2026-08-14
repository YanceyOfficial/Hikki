import { bucketActivityLevel } from '#lib/activity-level'

test.each([
  [0, 'none'],
  [1, 'low'],
  [2, 'low'],
  [3, 'medium'],
  [5, 'medium'],
  [6, 'high'],
  [20, 'high']
])('bucketActivityLevel(%i) is %s', (count, expected) => {
  expect(bucketActivityLevel(count)).toBe(expected)
})
