export function normalizeTracking(value) {
  return String(value ?? '').normalize('NFKC').replace(/[٠-٩]/g, c => String(c.charCodeAt(0)-1632)).replace(/[۰-۹]/g,c=>String(c.charCodeAt(0)-1776)).replace(/\s/g,'').toUpperCase();
}
export function validTracking(value) { return /^[A-Z0-9-]{6,50}$/.test(value); }
export function cents(value) {
  const s=String(value).trim().replace(',','.');
  if(!/^\d{1,6}(\.\d{1,2})?$/.test(s)) throw new Error('INVALID_AMOUNT');
  const [a,b='']=s.split('.'); return Number(a)*100+Number(b.padEnd(2,'0'));
}
