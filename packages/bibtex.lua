local lpeg = require("lpeg")
local epnf = require("epnf")

local identifier = (SILE.parserBits.identifier + lpeg.S":-")^1

local balanced = lpeg.C{ "{" * lpeg.P(" ")^0 * lpeg.C(((1 - lpeg.S"{}") + lpeg.V(1))^0) * "}" } / function (...) local t={...}; return t[2] end
local doubleq = lpeg.C( lpeg.P '"' * lpeg.C(((1 - lpeg.S '"\r\n\f\\') + (lpeg.P '\\' * 1)) ^ 0) * '"' )

-- luacheck: push ignore
local bibtexparser = epnf.define(function (_ENV)
  local _ = WS^0
  local sep = lpeg.S(",;") * _
  local myID = C(identifier + lpeg.P(1)) / function (t) return t end
  local value = balanced + doubleq + myID
  local pair = lpeg.Cg(myID * _ * "=" * _ * C(value)) * _ * sep^-1   / function (...) local t= {...}; return t[1], t[#t] end
  local list = lpeg.Cf(lpeg.Ct("") * pair^0, rawset)

  START "document"
  document = (V"entry" + V"comment")^1 * (-1 + E("Unexpected character at end of input"))
  comment  = WS +
    ( V"blockcomment" + (P("%") * (1-lpeg.S("\r\n"))^0 * lpeg.S("\r\n")) /function () return "" end) -- Don't bother telling me about comments
  blockcomment = P("@comment")+ balanced/function () return "" end -- Don't bother telling me about comments
  entry = Ct( P("@") * Cg(myID, "type") * _ * P("{") * _ * Cg(myID, "label") * _ * sep * list * P("}") * _ )
end)
-- luacheck: pop

local parseBibtex = function (fn)
  fn = SILE.resolveFile(fn)
  local fh,e = io.open(fn)
  if e then SU.error("Error reading bibliography file "..e) end
  local doc = fh:read("*all")
  local t = epnf.parsestring(bibtexparser, doc)
  if not(t) or not(t[1]) or t.id ~= "document" then
    SU.error("Error parsing bibtex")
  end
  local entries = {}
  for i =1,#t do
    if t[i].id == "entry" then
      local ent = t[i][1]
      entries[ent.label] = {type = ent.type, attributes = ent[1]}
    end
  end
  return entries
end

SILE.scratch.bibtex = { bib = {}, bibstyle = {} }
local Bibliography = SILE.require("packages/bibliography")

SILE.registerCommand("loadbibliography", function (options, _)
  local file = SU.required(options, "file", "loadbibliography")
  SILE.scratch.bibtex.bib = parseBibtex(file) -- Later we'll do multiple bibliogs, but not now
end)

SILE.registerCommand("bibstyle", function (_, content)
  SILE.scratch.bibtex.bibstyle = SILE.require("packages/bibstyles/"..content)
end)

SILE.call("bibstyle", {}, "chicago") -- Load some default

SILE.registerCommand("cite", function (options, content)
  if not options.key then options.key = content[1] end
  local cite = Bibliography.produceCitation(options, SILE.scratch.bibtex.bib, SILE.scratch.bibtex.bibstyle)
  if cite == Bibliography.Errors.UNKNOWN_REFERENCE then
    SU.warn("Unknown reference in citation "..options)
    return
  end
  SILE.doTexlike(cite)
end)

SILE.registerCommand("reference", function (options, content)
  if not options.key then options.key = content[1] end
  local cite = Bibliography.produceReference(options, SILE.scratch.bibtex.bib, SILE.scratch.bibtex.bibstyle)
  if cite == Bibliography.Errors.UNKNOWN_REFERENCE then
    SU.warn("Unknown reference in citation "..options)
    return
  end
  SILE.doTexlike(cite)
end)
