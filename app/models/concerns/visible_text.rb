# Strips whitespace and zero-width characters (ZWSP, ZWNJ, ZWJ, word joiner, BOM)
# from both ends, so "invisible" input cannot pass presence validations.
module VisibleText
  INVISIBLE_EDGES = /\A[[:space:]​-‍⁠﻿]+|[[:space:]​-‍⁠﻿]+\z/

  def self.strip(value)
    value.to_s.gsub(INVISIBLE_EDGES, "")
  end
end
