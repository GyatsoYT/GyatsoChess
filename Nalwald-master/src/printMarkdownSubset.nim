import std/[terminal, strutils]

proc printMarkdownSubsetNoNewline(markdown: string) =
  var
    markdown = markdown
    isTitle = false
    isInlineCode = false
    isCodeBlock = false
    isBright = false
    isItalic = false
    isUnderscore = false
    isBulletPoint = false
    couldBeBulletPoint = true
    currentString = ""

  func popFront(s: var string) =
    if s.len >= 1:
      s = s[1 ..^ 1]
    else:
      s = ""

  proc printCurrentString() =
    stdout.resetAttributes()
    if isCodeBlock or isInlineCode:
      stdout.setStyle {styleDim}

    if isItalic:
      stdout.setStyle {styleItalic}

    if isUnderscore:
      stdout.setStyle {styleUnderscore}

    if isBright:
      stdout.setStyle {styleBright}

    if isTitle:
      stdout.setStyle {styleBright, styleUnderscore}

    if isBulletPoint:
      stdout.setStyle {styleDim}

    stdout.write currentString
    stdout.resetAttributes()
    currentString = ""

  if markdown.len > 0 and markdown[0] == '#':
    isTitle = true

  while markdown.len > 0:
    if markdown[0] != '-' and markdown[0] notin Whitespace:
      couldBeBulletPoint = false

    if markdown[0] == '\n':
      printCurrentString()
      isTitle = false
      stdout.write "\n"
      markdown.popFront
      if isCodeBlock and markdown.len > 0:
        stdout.write "    "
      elif markdown.len > 1 and not isInlineCode:
        if markdown[0] == '#':
          isTitle = true
        if not isTitle:
          couldBeBulletPoint = true
    elif markdown.len >= 2 and markdown[0 .. 1] == "**":
      printCurrentString()
      isBright = not isBright
      markdown.popFront
      markdown.popFront
    elif markdown[0] == '*':
      printCurrentString()
      isItalic = not isItalic
      markdown.popFront
    elif markdown.len >= 4 and markdown[0 .. 3] == "````":
      printCurrentString()
      isUnderscore = not isUnderscore
      markdown.popFront
      markdown.popFront
      markdown.popFront
      markdown.popFront
    elif markdown.len >= 3 and markdown[0 .. 2] == "```":
      printCurrentString()
      isCodeBlock = not isCodeBlock
      markdown.popFront
      markdown.popFront
      markdown.popFront
    elif markdown[0] == '`':
      printCurrentString()
      isInlineCode = not isInlineCode
      markdown.popFront
    elif markdown[0] == '-' and couldBeBulletPoint:
      currentString &= "•"
      isBulletPoint = true
      printCurrentString()
      isBulletPoint = false
      couldBeBulletPoint = false
      markdown.popFront
    elif markdown[0] == '\\' and markdown.len >= 2 and markdown[1] in ['#', '*', '`', '-']:
      markdown.popFront
      currentString &= markdown[0]
      markdown.popFront
    else:
      currentString &= markdown[0]
      markdown.popFront


proc printMarkdownSubset*(markdownLines: varargs[string]) =
  var markdown = ""
  for line in markdownLines:
    markdown &= line

  if markdown.len > 0:
    if markdown[^1] != '\n':
      markdown &= "\n"
    printMarkdownSubsetNoNewline markdown
