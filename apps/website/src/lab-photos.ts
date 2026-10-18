/** Unsplash photos for /lab, hotlinked (their downloads were reported when picked); credit links carry utm. */
export const photos = {
  notebook: {
    url: 'https://images.unsplash.com/photo-1582319193453-d841c7a5e586?crop=entropy&cs=tinysrgb&fit=max&ixid=M3wxMDk4MzM2fDB8MXxzZWFyY2h8Nnx8bm90ZWJvb2slMjBkZXNrJTIwbW9ybmluZ3xlbnwwfDB8fHwxNzkyMTY3NzA3fDA&ixlib=rb-4.1.0&q=80',
    alt: 'blue book beside white pen',
    author: 'Markus Spiske',
    authorUrl: 'https://unsplash.com/@markusspiske?utm_source=hikki&utm_medium=referral'
  },
  pen: {
    url: 'https://images.unsplash.com/photo-1471107340929-a87cd0f5b5f3?crop=entropy&cs=tinysrgb&fit=max&ixid=M3wxMDk4MzM2fDB8MXxzZWFyY2h8MXx8cGFwZXIlMjBub3RlYm9vayUyMHBlbnxlbnwwfDB8fHwxNzkyMTY3NzA5fDA&ixlib=rb-4.1.0&q=80',
    alt: 'fountain pen on spiral book',
    author: 'Aaron Burden',
    authorUrl: 'https://unsplash.com/@aaronburden?utm_source=hikki&utm_medium=referral'
  },
  temple: {
    url: 'https://images.unsplash.com/photo-1548403374-728475ca2813?crop=entropy&cs=tinysrgb&fit=max&ixid=M3wxMDk4MzM2fDB8MXxzZWFyY2h8OXx8a3lvdG8lMjB0ZW1wbGV8ZW58MHwwfHx8MTc5MjE2NzcxMHww&ixlib=rb-4.1.0&q=80',
    alt: 'gray concrete stairs inside temple',
    author: 'yoshie yokouchi',
    authorUrl: 'https://unsplash.com/@yoshie_yokouchi?utm_source=hikki&utm_medium=referral'
  },
  neon: {
    url: 'https://images.unsplash.com/photo-1788359658152-883b952951e7?crop=entropy&cs=tinysrgb&fit=max&ixid=M3wxMDk4MzM2fDB8MXxzZWFyY2h8Nnx8dG9reW8lMjBzdHJlZXR8ZW58MHwwfHx8MTc5MjE2NzcxMnww&ixlib=rb-4.1.0&q=80',
    alt: 'Bright neon signs in Japanese characters lining a narrow street in Shibuya, Tokyo',
    author: 'Tom Podmore',
    authorUrl: 'https://unsplash.com/@tompodmore86?utm_source=hikki&utm_medium=referral'
  },
  brush: {
    url: 'https://images.unsplash.com/photo-1486303954368-398fea0e72cd?crop=entropy&cs=tinysrgb&fit=max&ixid=M3wxMDk4MzM2fDB8MXxzZWFyY2h8MXx8amFwYW5lc2UlMjBjYWxsaWdyYXBoeXxlbnwwfDB8fHwxNzkyMTY3NzE0fDA&ixlib=rb-4.1.0&q=80',
    alt: 'person holding black paint brush while painting black text on white paper',
    author: 'Niketh Vellanki',
    authorUrl: 'https://unsplash.com/@thenikyv?utm_source=hikki&utm_medium=referral'
  },
  reading: {
    url: 'https://images.unsplash.com/photo-1573142143200-2a6d95ae7352?crop=entropy&cs=tinysrgb&fit=max&ixid=M3wxMDk4MzM2fDB8MXxzZWFyY2h8MXx8bGlicmFyeSUyMHJlYWRpbmd8ZW58MHwwfHx8MTc5MjE2NzcxNnww&ixlib=rb-4.1.0&q=80',
    alt: 'woman reading book sitting beside electronic keyboard',
    author: 'Hümâ H. Yardım',
    authorUrl: 'https://unsplash.com/@humayardim?utm_source=hikki&utm_medium=referral'
  },
  leaves: {
    url: 'https://images.unsplash.com/photo-1773774235180-de511ea41bbe?crop=entropy&cs=tinysrgb&fit=max&ixid=M3wxMDk4MzM2fDB8MXxzZWFyY2h8NXx8d2luZG93JTIwbGlnaHQlMjBwbGFudHxlbnwwfDB8fHwxNzkyMTY3NzE4fDA&ixlib=rb-4.1.0&q=80',
    alt: 'Shadows of leaves cast on a sheer curtain',
    author: 'Ivan Pomoshchikov',
    authorUrl: 'https://unsplash.com/@littlezero?utm_source=hikki&utm_medium=referral'
  }
} as const

export type Photo = (typeof photos)[keyof typeof photos]

/** The photo at a width, in the format the browser prefers. */
export const photoSrc = (photo: Photo, width: number) => `${photo.url}&auto=format&w=${width}`
