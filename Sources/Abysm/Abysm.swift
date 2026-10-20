// Abysm builds on InternedStrings, so a name is written once with `@Interned` and never appears in the binary's
// string table; re-exporting it means an adopter writes both with one import.
@_exported public import InternedStrings
