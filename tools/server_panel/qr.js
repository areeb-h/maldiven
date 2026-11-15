/* Drift Station control panel: a small QR code encoder (ISO/IEC 18004).
 * Byte mode, error correction level M, versions 1-10 (up to 213 bytes), with
 * automatic mask selection. Written for this panel; no network, no dependencies.
 *
 *   const qr = DriftQR.encode("192.168.1.23");  // {size, get(x, y)}
 *   svg.innerHTML = DriftQR.toSvgPath(qr);       // one <path>, 1 unit per module
 */
(function () {
  "use strict";

  // Level M block structure per version: [ec codewords per block, [blocks, data codewords]...]
  const BLOCKS = [
    null,
    [10, [1, 16]], [16, [1, 28]], [26, [1, 44]], [18, [2, 32]], [24, [2, 43]],
    [16, [4, 27]], [18, [4, 31]], [22, [2, 38], [2, 39]], [22, [3, 36], [2, 37]], [26, [4, 43], [1, 44]],
  ];
  const ALIGN = [null, [], [6, 18], [6, 22], [6, 26], [6, 30], [6, 34],
    [6, 22, 38], [6, 24, 42], [6, 26, 46], [6, 28, 50]];
  const ECL_M = 0; // format bits for level M

  // GF(256) with the QR polynomial x^8 + x^4 + x^3 + x^2 + 1.
  const EXP = new Uint8Array(512);
  const LOG = new Uint8Array(256);
  for (let i = 0, x = 1; i < 255; i++) {
    EXP[i] = x;
    LOG[x] = i;
    x <<= 1;
    if (x & 0x100) x ^= 0x11d;
  }
  for (let i = 255; i < 512; i++) EXP[i] = EXP[i - 255];
  const mul = (a, b) => (a && b ? EXP[LOG[a] + LOG[b]] : 0);

  function generator(degree) {
    let poly = [1];
    for (let i = 0; i < degree; i++) {
      const next = new Array(poly.length + 1).fill(0);
      for (let j = 0; j < poly.length; j++) {
        next[j] ^= poly[j];
        next[j + 1] ^= mul(poly[j], EXP[i]);
      }
      poly = next;
    }
    return poly;
  }

  function remainder(data, degree) {
    const gen = generator(degree);
    const out = new Array(degree).fill(0);
    for (const byte of data) {
      const factor = byte ^ out.shift();
      out.push(0);
      for (let i = 0; i < degree; i++) out[i] ^= mul(gen[i + 1], factor);
    }
    return out;
  }

  function utf8(text) {
    return Array.from(new TextEncoder().encode(String(text)));
  }

  function dataCapacity(version) {
    const spec = BLOCKS[version];
    let total = 0;
    for (let g = 1; g < spec.length; g++) total += spec[g][0] * spec[g][1];
    return total;
  }

  // Data codewords: mode, count, bytes, terminator, padding.
  function codewords(bytes, version) {
    const bits = [];
    const put = (value, length) => {
      for (let i = length - 1; i >= 0; i--) bits.push((value >>> i) & 1);
    };
    put(0b0100, 4);
    put(bytes.length, version < 10 ? 8 : 16);
    for (const b of bytes) put(b, 8);
    const capacity = dataCapacity(version) * 8;
    put(0, Math.min(4, capacity - bits.length));
    while (bits.length % 8) bits.push(0);
    const out = [];
    for (let i = 0; i < bits.length; i += 8) {
      let v = 0;
      for (let j = 0; j < 8; j++) v = (v << 1) | bits[i + j];
      out.push(v);
    }
    for (let pad = 0; out.length < capacity / 8; pad++) out.push(pad % 2 ? 0x11 : 0xec);
    return out;
  }

  // Split into blocks, add Reed-Solomon codewords, interleave.
  function interleave(data, version) {
    const spec = BLOCKS[version];
    const ec = spec[0];
    const blocks = [];
    let offset = 0;
    for (let g = 1; g < spec.length; g++) {
      for (let b = 0; b < spec[g][0]; b++) {
        const chunk = data.slice(offset, offset + spec[g][1]);
        offset += spec[g][1];
        blocks.push({ data: chunk, ec: remainder(chunk, ec) });
      }
    }
    const out = [];
    const longest = Math.max(...blocks.map((b) => b.data.length));
    for (let i = 0; i < longest; i++) for (const b of blocks) if (i < b.data.length) out.push(b.data[i]);
    for (let i = 0; i < ec; i++) for (const b of blocks) out.push(b.ec[i]);
    return out;
  }

  function bch(value, poly) {
    const degree = Math.floor(Math.log2(poly));
    let v = value << degree;
    while (v && Math.floor(Math.log2(v)) >= degree) v ^= poly << (Math.floor(Math.log2(v)) - degree);
    return (value << degree) | v;
  }

  const MASKS = [
    (x, y) => (x + y) % 2 === 0,
    (x, y) => y % 2 === 0,
    (x) => x % 3 === 0,
    (x, y) => (x + y) % 3 === 0,
    (x, y) => (Math.floor(y / 2) + Math.floor(x / 3)) % 2 === 0,
    (x, y) => ((x * y) % 2) + ((x * y) % 3) === 0,
    (x, y) => (((x * y) % 2) + ((x * y) % 3)) % 2 === 0,
    (x, y) => (((x + y) % 2) + ((x * y) % 3)) % 2 === 0,
  ];

  function build(version, stream, mask) {
    const size = version * 4 + 17;
    const dark = new Uint8Array(size * size);
    const fixed = new Uint8Array(size * size);
    const set = (x, y, on, isFixed = true) => {
      if (x < 0 || y < 0 || x >= size || y >= size) return;
      dark[y * size + x] = on ? 1 : 0;
      if (isFixed) fixed[y * size + x] = 1;
    };
    // Finder patterns with separators.
    for (const [fx, fy] of [[0, 0], [size - 7, 0], [0, size - 7]]) {
      for (let dy = -1; dy <= 7; dy++) {
        for (let dx = -1; dx <= 7; dx++) {
          const ring = Math.max(Math.abs(dx - 3), Math.abs(dy - 3));
          set(fx + dx, fy + dy, ring !== 2 && ring !== 4);
        }
      }
    }
    // Alignment patterns (skipping the three that would overlap the finders).
    const centers = ALIGN[version];
    for (const cy of centers) {
      for (const cx of centers) {
        if ((cx === 6 && cy === 6) || (cx === 6 && cy === size - 7) || (cx === size - 7 && cy === 6)) continue;
        for (let dy = -2; dy <= 2; dy++) {
          for (let dx = -2; dx <= 2; dx++) set(cx + dx, cy + dy, Math.max(Math.abs(dx), Math.abs(dy)) !== 1);
        }
      }
    }
    // Timing patterns.
    for (let i = 8; i < size - 8; i++) {
      set(i, 6, i % 2 === 0);
      set(6, i, i % 2 === 0);
    }
    // Format information (with the always-dark module).
    const format = bch((ECL_M << 3) | mask, 0x537) ^ 0x5412;
    for (let i = 0; i < 15; i++) {
      const on = ((format >>> i) & 1) === 1;
      // First copy, around the top-left finder (skipping the timing row/column).
      if (i <= 5) set(8, i, on);
      else if (i === 6) set(8, 7, on);
      else if (i === 7) set(8, 8, on);
      else if (i === 8) set(7, 8, on);
      else set(14 - i, 8, on);
      // Second copy, split between the top-right and bottom-left finders.
      if (i < 8) set(size - 1 - i, 8, on);
      else set(8, size - 15 + i, on);
    }
    set(8, size - 8, true);
    // Version information (v7+).
    if (version >= 7) {
      const info = bch(version, 0x1f25);
      for (let i = 0; i < 18; i++) {
        const on = ((info >>> i) & 1) === 1;
        const a = Math.floor(i / 3);
        const b = (i % 3) + size - 11;
        set(a, b, on);
        set(b, a, on);
      }
    }
    // Data, in the zig-zag column pairs from the bottom right.
    let bit = 0;
    const total = stream.length * 8;
    for (let right = size - 1; right >= 1; right -= 2) {
      if (right === 6) right = 5;
      for (let vert = 0; vert < size; vert++) {
        for (let j = 0; j < 2; j++) {
          const x = right - j;
          const upward = ((right + 1) & 2) === 0;
          const y = upward ? size - 1 - vert : vert;
          if (fixed[y * size + x]) continue;
          let on = false;
          if (bit < total) on = ((stream[bit >>> 3] >>> (7 - (bit & 7))) & 1) === 1;
          bit++;
          if (MASKS[mask](x, y)) on = !on;
          dark[y * size + x] = on ? 1 : 0;
        }
      }
    }
    return { size, dark };
  }

  function penalty({ size, dark }) {
    const at = (x, y) => dark[y * size + x];
    let score = 0;
    // Rule 1: runs of 5+ same-coloured modules in a row or column.
    for (let pass = 0; pass < 2; pass++) {
      for (let a = 0; a < size; a++) {
        let run = 1;
        for (let b = 1; b < size; b++) {
          const same = pass ? at(a, b) === at(a, b - 1) : at(b, a) === at(b - 1, a);
          if (same) {
            run++;
            if (run === 5) score += 3;
            else if (run > 5) score += 1;
          } else run = 1;
        }
      }
    }
    // Rule 2: 2x2 blocks.
    for (let y = 0; y < size - 1; y++) {
      for (let x = 0; x < size - 1; x++) {
        const c = at(x, y);
        if (c === at(x + 1, y) && c === at(x, y + 1) && c === at(x + 1, y + 1)) score += 3;
      }
    }
    // Rule 3: finder-like 1:1:3:1:1 patterns with 4 light modules on one side.
    const patterns = [[1, 0, 1, 1, 1, 0, 1, 0, 0, 0, 0], [0, 0, 0, 0, 1, 0, 1, 1, 1, 0, 1]];
    for (let a = 0; a < size; a++) {
      for (let b = 0; b <= size - 11; b++) {
        for (const p of patterns) {
          let row = true;
          let col = true;
          for (let k = 0; k < 11; k++) {
            if (at(b + k, a) !== p[k]) row = false;
            if (at(a, b + k) !== p[k]) col = false;
          }
          if (row) score += 40;
          if (col) score += 40;
        }
      }
    }
    // Rule 4: balance of dark and light.
    let darkCount = 0;
    for (const v of dark) darkCount += v;
    score += Math.floor(Math.abs((darkCount * 100) / (size * size) - 50) / 5) * 10;
    return score;
  }

  function encode(text, forceMask) {
    const bytes = utf8(text);
    let version = 1;
    while (version <= 10 && dataCapacity(version) < bytes.length + (version < 10 ? 2 : 3)) version++;
    if (version > 10) throw new Error("Text too long for a QR code here");
    const stream = interleave(codewords(bytes, version), version);
    let best = null;
    let bestScore = Infinity;
    for (let mask = 0; mask < 8; mask++) {
      if (forceMask !== undefined && mask !== forceMask) continue;
      const candidate = build(version, stream, mask);
      const score = penalty(candidate);
      if (score < bestScore) {
        best = candidate;
        bestScore = score;
      }
    }
    return { version, size: best.size, dark: best.dark, get: (x, y) => best.dark[y * best.size + x] === 1 };
  }

  // One SVG path in module units (viewBox "0 0 size size"), horizontal runs merged.
  function toSvgPath(qr) {
    let d = "";
    for (let y = 0; y < qr.size; y++) {
      let x = 0;
      while (x < qr.size) {
        if (!qr.get(x, y)) {
          x++;
          continue;
        }
        let end = x;
        while (end < qr.size && qr.get(end, y)) end++;
        d += `M${x} ${y}h${end - x}v1h${x - end}z`;
        x = end;
      }
    }
    return d;
  }

  const api = { encode, toSvgPath };
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  if (typeof window !== "undefined") window.DriftQR = api;
})();
