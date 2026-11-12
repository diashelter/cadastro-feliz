import { createHash } from 'node:crypto';
import { isIPv4, isIPv6 } from 'node:net';

// As chaves do redis-limiter, com a regra de hash de docs/api-contract.md › Chave e IP do cliente.

const sha256 = (text: string): string => createHash('sha256').update(text, 'utf8').digest('hex');

export function attemptsKey(ip: string, email: string): string {
  return `registration:attempts:${sha256(`${canonicalIp(ip)}|${email}`)}`;
}

export function quotaKey(ip: string): string {
  return `registration:ip:${sha256(canonicalIp(ip))}`;
}

/** IPv4 como está; IPv4 mapeado em IPv6 vira IPv4; IPv6 comprimido e em minúsculas (RFC 5952), sem zona. */
export function canonicalIp(raw: string): string {
  const ip = raw.split('%', 1)[0];
  if (isIPv4(ip)) {
    return ip;
  }
  if (!isIPv6(ip)) {
    return ip;
  }
  const groups = ipv6Groups(ip);
  if (groups.slice(0, 5).every((g) => g === 0) && groups[5] === 0xffff) {
    return [groups[6] >> 8, groups[6] & 0xff, groups[7] >> 8, groups[7] & 0xff].join('.');
  }
  return formatIpv6(groups);
}

function ipv6Groups(ip: string): number[] {
  let text = ip.toLowerCase();
  const tail = text.match(/(\d+\.\d+\.\d+\.\d+)$/);
  if (tail) {
    const [a, b, c, d] = tail[1].split('.').map(Number);
    text = text.slice(0, -tail[1].length) + `${((a << 8) | b).toString(16)}:${((c << 8) | d).toString(16)}`;
  }
  const [head, rest] = text.includes('::') ? text.split('::') : [text, undefined];
  const left = head ? head.split(':') : [];
  const right = rest === undefined ? [] : rest ? rest.split(':') : [];
  const zeros = rest === undefined ? 0 : 8 - left.length - right.length;
  return [...left, ...Array<string>(zeros).fill('0'), ...right].map((g) => Number.parseInt(g, 16));
}

function formatIpv6(groups: number[]): string {
  let bestStart = -1;
  let bestLength = 0;
  for (let i = 0; i < 8; ) {
    if (groups[i] !== 0) {
      i++;
      continue;
    }
    let j = i;
    while (j < 8 && groups[j] === 0) j++;
    if (j - i > bestLength) {
      bestStart = i;
      bestLength = j - i;
    }
    i = j;
  }
  const hex = groups.map((g) => g.toString(16));
  if (bestLength < 2) {
    return hex.join(':');
  }
  return `${hex.slice(0, bestStart).join(':')}::${hex.slice(bestStart + bestLength).join(':')}`;
}
