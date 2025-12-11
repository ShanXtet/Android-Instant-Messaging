/**
 * Normalize phone number to consistent format: +<digits>
 * Examples:
 *  "1111111111"      -> "+1111111111"
 *  "+111 111 1111"   -> "+1111111111"
 *  "  +111-111-1111" -> "+1111111111"
 */
export const normalizePhone = (phone) => {
  if (!phone) return '';
  const raw = phone.toString().trim();
  const digits = raw.replace(/\D/g, ''); // keep digits only
  if (!digits) return '';
  return `+${digits}`;
};

/**
 * Validate phone number format
 */
export const isValidPhone = (phone) => {
  const normalized = normalizePhone(phone);
  return normalized.length >= 10 && /^\+?\d{10,}$/.test(normalized);
};

