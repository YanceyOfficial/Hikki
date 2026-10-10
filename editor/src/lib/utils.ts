import { clsx, type ClassValue } from 'clsx'
import { twMerge } from 'tailwind-merge'

/** shadcn's class joiner: conditional classes (clsx) with Tailwind conflicts resolved (twMerge). */
export function cn(...inputs: ClassValue[]): string {
  return twMerge(clsx(inputs))
}
