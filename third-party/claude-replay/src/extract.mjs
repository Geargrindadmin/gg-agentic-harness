/**
 * Extract embedded turn/bookmark data from a generated HTML replay file.
 */

import { inflateSync } from "node:zlib";

/**
 * Decode a data blob — either raw JSON or base64-encoded deflate.
 * @param {string} raw
 * @returns {unknown}
 */
function decodeBlob(raw) {
  if (raw.startsWith("[") || raw.startsWith("{")) {
    // Raw JSON (--no-compress mode) — undo script-safe escaping
    return JSON.parse(raw.replace(/<\\\//g, "</").replace(/<\\!--/g, "<!--"));
  }
  // Compressed: base64-encoded deflate
  return JSON.parse(inflateSync(Buffer.from(raw, "base64")).toString());
}

/**
 * Find all data blobs passed to the async decode function.
 * Works with both minified (e.g. `f=await Tt("...")`) and
 * unminified (`const TURNS = await decodeData("...")`) output.
 * Returns blobs in source order: [turnsBlob, bookmarksBlob].
 * @param {string} html
 * @returns {string[]}
 */
function findBlobs(html) {
  const blobs = [];
  const pattern = /await\s+\w+\("/g;
  let m;
  while ((m = pattern.exec(html)) !== null) {
    const start = m.index + m[0].length;
    const end = html.indexOf('");', start);
    if (end !== -1 && end > start) {
      blobs.push(html.slice(start, end));
    }
  }
  return blobs;
}

/**
 * Extract turns and bookmarks from a generated HTML replay string.
 * @param {string} html
 * @returns {{ turns: object[], bookmarks: object[] }}
 */
export function extractData(html) {
  const blobs = findBlobs(html);

  // The template has exactly two decode calls: TURNS first, BOOKMARKS second.
  if (blobs.length < 2) {
    throw new Error("Could not find data blobs in HTML (expected at least 2 decodeData calls)");
  }

  return {
    turns: decodeBlob(blobs[0]),
    bookmarks: decodeBlob(blobs[1]),
  };
}
