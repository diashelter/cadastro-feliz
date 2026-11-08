/** A espera antes de uma nova tentativa de envio (decisão 9 de docs/decisions.md). */
export function retryDelaySeconds(previousAttempts: number, base: number): number {
  return base * 2 ** previousAttempts;
}
