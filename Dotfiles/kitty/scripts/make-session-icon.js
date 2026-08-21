// Renders one session-app icon: a rounded square in the session's colour with
// a big white letter on it. Called by make-session-apps.sh as:
//
//   osascript -l JavaScript make-session-icon.js <letter> <r> <g> <b> <out.png>
//
// JXA's Objective-C bridge is used because this machine has no ImageMagick,
// no librsvg and no Python PIL - but AppKit is always present on macOS, so
// this needs no dependencies at all.
//
// Two bridge gotchas that cost time, don't "simplify" them back:
//   - Selector names camel-case EVERY part, including the ones after the
//     first colon: bezierPathWithRoundedRect:xRadius:yRadius: becomes
//     bezierPathWithRoundedRectXRadiusYRadius (capital R), not ...Xradius.
//   - $.NSFontAttributeName / $.NSForegroundColorAttributeName come back
//     undefined through the bridge; the plain string keys 'NSFont' and
//     'NSColor' are what NSAttributedString actually uses internally.
//
// Note the output PNG comes out at 2x the nominal size (2048px for S=1024):
// lockFocus renders into a backing store at the main display's scale factor,
// which is 2 on a Retina Mac. That's harmless - sips downsamples it into
// every iconset size anyway - but it's why the file isn't 1024px.

ObjC.import('AppKit');

const args = ObjC.deepUnwrap($.NSProcessInfo.processInfo.arguments);
const [letter, r, g, b, out] = args.slice(-5);

const S = 1024;
const img = $.NSImage.alloc.initWithSize($.NSMakeSize(S, S));
img.lockFocus;

// Rounded square, inset slightly so the icon doesn't touch the tile edges.
const rect = $.NSMakeRect(S * 0.06, S * 0.06, S * 0.88, S * 0.88);
$.NSColor.colorWithSRGBRedGreenBlueAlpha(
  parseFloat(r), parseFloat(g), parseFloat(b), 1.0
).set;
$.NSBezierPath.bezierPathWithRoundedRectXRadiusYRadius(rect, S * 0.22, S * 0.22).fill;

const attrs = $.NSMutableDictionary.alloc.init;
attrs.setObjectForKey($.NSFont.boldSystemFontOfSize(S * 0.52), 'NSFont');
attrs.setObjectForKey($.NSColor.whiteColor, 'NSColor');

const str = $.NSString.alloc.initWithUTF8String(letter);
const sz = str.sizeWithAttributes(attrs);
str.drawAtPointWithAttributes(
  $.NSMakePoint((S - sz.width) / 2, (S - sz.height) / 2), attrs
);

img.unlockFocus;

const rep = $.NSBitmapImageRep.imageRepWithData(img.TIFFRepresentation);
// 4 == NSBitmapImageFileTypePNG; the $.NSPNGFileType constant is not bridged.
const png = rep.representationUsingTypeProperties(4, $.NSDictionary.dictionary);
png.writeToFileAtomically($(out), true);
