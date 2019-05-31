if not SILE.scratch.counters then SILE.scratch.counters = {} end

local textcase = SILE.require("packages/textcase").exports

local romans = {
  {1000, "M"},
  {900, "CM"}, {500, "D"}, {400, "CD"}, {100, "C"},
  {90, "XC"}, {50, "L"}, {40, "XL"}, {10, "X"},
  {9, "IX"}, {5, "V"}, {4, "IV"}, {1, "I"}
}

local function num2roman(num)
  local out = ""
  num = num + 0
  for _, v in ipairs(romans) do
    val, let = unpack(v)
    while num >= val do
      num = num - val
      out = out .. let
    end
  end
  return out
end

local num2alpha = function (num)
  local out = ""
  local a = string.byte("a")
  repeat
    num = num - 1
    out = string.char(num % 26 + a) .. out
    num = (num - num % 26) / 26
  until num < 1
  return out
end

local icu = require("justenoughicu")

SILE.formatCounter = function(counter)
  local lang = SILE.settings.get("document.language")
  local num2string, num2ordinal

  local LS = SILE.languageSupport.languages[lang]
  if LS then
    if LS.formatCounter then
      local result = LS.formatCounter(counter)
      if result then return result end
    end
    num2alpha = LS.num2alpha and LS.num2alpha or num2alpha
    num2roman = LS.num2roman and LS.num2roman or num2roman
    num2string = LS.num2string and LS.num2string or num2string
    num2ordinal = LS.num2ordinal and LS.num2ordinal or num2ordinal
  end

  -- If we have ICU, try that
  if icu then
    local display = counter.display
    -- Translate numbering style names which are different in ICU
    if display == "roman" then display = "romanlow"
    elseif display == "Roman" then display = "roman"
    end
    local ok, result = pcall(function() return icu.format_number(counter.value, display) end)
    if ok then return result end
  end

  if (counter.display == "string") and num2string then return textcase.lowercase(num2string(counter.value)) end
  if (counter.display == "String") and num2string then return textcase.titlecase(num2string(counter.value)) end
  if (counter.display == "STRING") and num2string then return textcase.uppercase(num2string(counter.value)) end
  if (counter.display == "ordinal") and num2ordinal then return textcase.lowercase(num2ordinal(counter.value)) end
  if (counter.display == "Ordinal") and num2ordinal then return textcase.titlecase(num2ordinal(counter.value)) end
  if (counter.display == "ORDINAL") and num2ordinal then return textcase.uppercase(num2ordinal(counter.value)) end
  if (counter.display == "roman") then return num2roman(counter.value):lower() end
  if (counter.display == "Roman" or counter.display == "ROMAN") then return num2roman(counter.value) end
  if (counter.display == "alpha") then return num2alpha(counter.value) end
  if (counter.display == "Alpha" or counter.display =="ALPHA") then return textcase.uppercase(num2alpha(counter.value)) end
  return tostring(counter.value)
end

local function getCounter(id)
  if not SILE.scratch.counters[id] then
    SILE.scratch.counters[id] = { value = 0, display = "arabic", format = SILE.formatCounter }
  end
  return SILE.scratch.counters[id]
end

SILE.registerCommand("increment-counter", function (options, content)
  local counter = getCounter(options.id)
  if (options["set-to"]) then
    counter.value = tonumber(options["set-to"])
  else
    counter.value = counter.value + 1
  end
  if options.display then counter.display = options.display end
end, "Increments the counter named by the <id> option")

SILE.registerCommand("set-counter", function (options, content)
  local counter = getCounter(options.id)
  if options.value then counter.value = tonumber(options.value) end
  if options.display then counter.display = options.display end
end, "Sets the counter named by the <id> option to <value>; sets its display type (roman/Roman/arabic) to type <display>.")


SILE.registerCommand("show-counter", function (options, content)
  local counter = getCounter(options.id)
  if options.display then counter.display = options.display end
  SILE.typesetter:setpar(SILE.formatCounter(counter))
end, "Outputs the value of counter <id>, optionally displaying it with the <display> format.")

SILE.formatMultilevelCounter = function(counter, options)
  local maxlevel = options and options.level or #counter.value
  local minlevel = options and options.minlevel or 1
  local out = {}
  for x = minlevel, maxlevel do
    out[x - minlevel + 1] = SILE.formatCounter({ display = counter.display[x], value = counter.value[x] })
  end
  return table.concat( out, "." )
end

local function getMultilevelCounter(id)
  local counter = SILE.scratch.counters[id]
  if not counter then
    counter = { value= {0}, display= {"arabic"}, format = SILE.formatMultilevelCounter }
    SILE.scratch.counters[id] = counter
  end
  return counter
end

SILE.registerCommand("increment-multilevel-counter", function (options, content)
  local counter = getMultilevelCounter(options.id)
  local currentLevel = #counter.value
  local level = tonumber(options.level) or currentLevel
  if level == currentLevel then
    counter.value[level] = counter.value[level] + 1
  elseif level > currentLevel then
    while level > currentLevel do
      currentLevel = currentLevel + 1
      counter.value[currentLevel] = (options.reset == false) and counter.value[currentLevel -1 ] or 1
      counter.display[currentLevel] = counter.display[currentLevel - 1]
    end
  else -- level < currentLevel
    counter.value[level] = counter.value[level] + 1
    while currentLevel > level do
      if not (options.reset == false) then counter.value[currentLevel] = nil end
      counter.display[currentLevel] = nil
      currentLevel = currentLevel - 1
    end
  end
  if options.display then counter.display[currentLevel] = options.display end
end)

SILE.registerCommand("show-multilevel-counter", function (options, content)
  local counter = getMultilevelCounter(options.id)
  if options.display then counter.display[#counter.value] = options.display end

  SILE.typesetter:typeset(SILE.formatMultilevelCounter(counter, options))
end, "Outputs the value of the multilevel counter <id>, optionally displaying it with the <display> format.")

return {
  exports = {
    getCounter = getCounter,
    getMultilevelCounter = getMultilevelCounter
  },
  documentation = [[\begin{document}

Various parts of SILE such as the \code{footnotes} package and the
sectioning commands keep a counter of things going on: the current
footnote number, the chapter number, and so on. The counters package
allows you to set up, increment and typeset named counters. It
provides the following commands:

• \code{\\set-counter[id=\em{<counter-name>},value=\em{<value}]} — sets
the counter called \code{<counter-name>} to the value given.

• \code{\\increment-counter[id=\em{<counter-name>}]} — does the
same as \code{\\set-counter} except that when no \code{value} parameter
is given, the counter is incremented by one.

• \code{\\show-counter[id=\em{<counter-name>}]} — this typesets the
value of the counter according to the counter’s declared display type.

\note{All of the commands in the counters package take an optional
\code{display=\em{<display-type>}} parameter
to set the \em{display type} of the counter.

The available built-in display types are: \code{arabic}, the default;
\code{alpha}, for alphabetic counting;
\code{roman}, for lower-case Roman numerals; and \code{Roman} for upper-case
Roman numerals.

The ICU library also provides ways of formatting numbers in global (non-Latin)
scripts. You can use any of the display types in this list:
\url{http://www.unicode.org/repos/cldr/tags/latest/common/bcp47/number.xml}.
For example, \code{display=beng} will format your numbers in Bengali digits.
}


So, for example, the following SILE code:

\begin{verbatim}
\line
\\set-counter[id=mycounter, value=2]
\\show-counter[id=mycounter]

\\increment-counter[id=mycounter]
\\show-counter[id=mycounter, display=roman]
\line
\end{verbatim}

produces:

\line
\examplefont{2

\noindent{}iii}
\line
\end{document}]] }
