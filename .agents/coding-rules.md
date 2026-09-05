# Coding Rules

These rules describe how we write and maintain MaxScript code in this project.

## Language And Character Set

- Use English written with Latin characters for all project-authored content.
- Do not use Cyrillic characters in source code, identifiers, filenames, comments, documentation, UI labels, dialogs, prompts, logs, warnings, errors, release scripts, or configuration text.
- Prefer plain ASCII for code-facing text whenever possible. Digits and standard programming punctuation are allowed.
- Preserve external user data as-is when it must be displayed or processed; do not introduce non-Latin text into project-authored strings.
- Before completing a change, scan every modified text file for Cyrillic characters and remove any matches introduced by the change.

## MaxScript Functions

- Always use an explicit `return` when a function produces a result.
- Do not leave a "lonely" variable or expression as the last line of a function and rely on it as an implicit return value.
- Return `true` or `false` explicitly from functions that report success/failure.
- Use early `return` for guard clauses when it makes the function easier to read.

Example:

```maxscript
fn isValidFile f = (
	if (f == undefined or f == "") do return false
	if (not doesFileExist f) do return false
	return true
)
```

## Variables

- Use `local` for internal function variables.
- Do not leak temporary variables into global scope.
- Use descriptive names that explain intent.
- Do not use reserved or ambiguous names such as `ok`, because some names can conflict with MaxScript reserved values or built-in behavior.
- Prefer names such as `isSuccess`, `isValid`, `hasError`, `uploadResult`, `errorMessage`, `responseBody`.

Example:

```maxscript
local isUploaded = awsUploaderMgr.upload file
if (isUploaded) then (
	return true
) else (
	return false
)
```

## Data Bundles And Structs

- When several values describe one logical runtime object, pass them as a small named `struct` instead of passing many separate arguments.
- Prefer a structure for grouped data such as file metadata, options, processing results, or validation details.
- Name fields by meaning, for example `filename`, `options`, `val`, `errors`, `warnings`, `isSuccess`.
- Keep these structs focused on data. Do not turn a temporary data bundle into a manager unless it owns behavior.
- Use named struct arguments or explicit field assignment so call sites stay readable.
- Keep temporary data structs close to the code that owns them. If a data struct is only used by one wrapper/factory, define it inside that wrapper/factory instead of adding another global type at the top of the file.
- Prefer passing one readable data struct through several functions over passing parallel arrays or relying on array indexes such as `item[1]`, `item[2]`, `item[3]`.
- `tmp` is acceptable only as a short-lived local variable; the struct type itself should have a meaningful name.

Example:

```maxscript
struct TempProcessData (
	filename,
	options,
	val
)

local tmp = TempProcessData filename: file options: processOptions val: initialValue
local result = processFile tmp
```

Avoid:

```maxscript
local result = processFile file processOptions initialValue
```

## Loops

- Use `for i in 1 to count do (...)` style for numeric ranges.
- Do not use `for i = 1 to count do (...)` in project MaxScript code.

Example:

```maxscript
for i in 1 to items.count do (
	print items[i]
)
```

## Error Handling

- Wrap optional, debug, watchdog, UI, and external integration calls in `try/catch` when failure should not stop the conversion.
- Do not hide important processing errors that must stop the current queue item.
- If an error should be visible to the server, send it through `requestMgr.postLog` or the existing process logging helper.
- If a function catches an error and continues, make sure the fallback behavior is intentional.

Example:

```maxscript
try (watchdogMgr.beat stage: "converting_glb") catch()
```

## Scope And State

- Keep globals limited to shared managers, UI rollout references, and configuration that truly needs to be shared.
- Prefer passing values into functions instead of reading unrelated global state inside helpers.
- Do not mutate UI checkbox/settings values just to change one processing attempt. Use a local runtime flag instead.

## UI

- Keep UI state and runtime processing state separate.
- If a setting is saved from UI, use the existing settings pattern for that rollout.
- When adding a new setting, provide a safe default and load it on startup.
- Error messages shown to the user should explain what is missing or what failed.

## Git And Release Hygiene

- Do not commit credentials, local settings, generated runtime files, or test-only local data.
- Before release, run:
- Follow `release.md` for version bumps, changelog updates, commits, and pushes.
