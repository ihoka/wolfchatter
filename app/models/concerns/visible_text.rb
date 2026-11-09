# Strips whitespace and zero-width characters (ZWSP, ZWNJ, ZWJ, word joiner, BOM)
# from both ends, so "invisible" input cannot pass presence validations.
#
# The list is deliberately partial: the soft hyphen, the Hangul filler and bidi
# control characters are not covered. Names are honor-system, not identity.
# Escapes (not literal characters) keep invisible characters out of the source.
module VisibleText
  INVISIBLE_EDGES = /\A[[:space:]\u200B-\u200D\u2060\uFEFF]+|[[:space:]\u200B-\u200D\u2060\uFEFF]+\z/

  def self.strip(value)
    value.to_s.gsub(INVISIBLE_EDGES, "")
  end
end
