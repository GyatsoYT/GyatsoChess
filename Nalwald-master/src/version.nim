import std/[strutils, options]

export options

func compileDate*(): string =
  CompileDate & " " & CompileTime & " (UTC)"
func compileYear*(): string =
  CompileDate.split('-')[0]

when "git version" notin staticExec("git --version") or
    staticExec("git rev-parse --is-inside-work-tree").strip != "true":
  static:
    debugEcho "WARNING: Git not available or not a git repo"
    debugEcho "git --version: ",
      staticExec("git --version"), "\ngit status: ", staticExec("git status")

  const gitHasUnstagedChanges* = false

  func version*(): Option[string] =
    none(string)

  func id(): string =
    const d = CompileDate.split('-')
    const t = CompileTime.split(':')
    "unspecified-" & d[0] & d[1] & d[2] & t[0] & t[1] & t[2]

  func commitHash*(): string =
    "unspecified"
else:
  const
    gitHasUnstagedChanges* = staticExec("git status -suno").strip != ""
    gitHash = staticExec("git rev-parse HEAD").strip
    gitShortHash = staticExec("git rev-parse --short HEAD").strip
    gitTag = staticExec("git tag --points-at HEAD").strip

  func version*(): Option[string] =
    when not gitTag.isEmptyOrWhitespace and not gitHasUnstagedChanges:
      some gitTag
    else:
      none string

  func id(): string =
    result = gitShortHash
    when gitHasUnstagedChanges:
      const d = CompileDate.split('-')
      const t = CompileTime.split(':')
      result &= "-" & d[0] & d[1] & d[2] & t[0] & t[1] & t[2]

  func commitHash*(): string =
    result = gitHash
    when gitHasUnstagedChanges:
      result &= " + unstaged changes"

func versionOrId*(): string =
  version().get(otherwise = id())
