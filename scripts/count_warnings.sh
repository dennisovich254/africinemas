#!/usr/bin/env bash
# Count real warnings in `jac check` output read from stdin.
# Discounts ONLY the checker false positive where a closing HTML tag in JSX is reported as
# an undefined name (W2001 "Name 'div' may be undefined": docs/jac-issues/JI-017).
# A genuinely undefined name (anything that isn't an HTML element) is still counted.
set -uo pipefail
html='a|abbr|address|article|aside|audio|b|blockquote|body|br|button|canvas|caption|code|col|dd|details|dialog|div|dl|dt|em|fieldset|figcaption|figure|footer|form|h1|h2|h3|h4|h5|h6|head|header|hr|html|i|iframe|img|input|label|legend|li|link|main|mark|menu|meter|nav|ol|optgroup|option|output|p|picture|pre|progress|q|section|select|small|source|span|strong|sub|summary|sup|svg|path|circle|rect|line|g|polyline|polygon|table|tbody|td|template|textarea|tfoot|th|thead|time|tr|u|ul|video'
grep -E '^⚠' | grep -v -E "W2001\]: Name '(${html})' may be undefined" | grep -c . || true
