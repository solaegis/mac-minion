#!/bin/zsh
# Checks the mechanical macOS UI rules in design/MACOS-UI-ARCHITECTURE.md (section 11).
# Usage: tools/hig-lint.sh [folder]      (default: Sources/MacMinion)
# Errors fail the run; warnings print but pass.
# Silence one line with a reason: // hig: ok <why>
# The token files (Theme.swift, Motion.swift) and the debug grid overlay (Grid.swift) are skipped.
set -euo pipefail
dir=${1:-${0:A:h:h}/Sources/MacMinion}
find "$dir" -name '*.swift' -not -name 'Theme.swift' -not -name 'Motion.swift' -not -name 'Grid.swift' -print0 | xargs -0 perl -e '
  my ($errors, $warnings) = (0, 0);
  sub report { my ($kind, $file, $n, $what, $line) = @_; $line =~ s/^\s+//; $line =~ s/\s+$//;
    print "$file:$n: $kind $what: $line\n"; $kind eq "error" ? $errors++ : $warnings++ }
  for my $file (@ARGV) {
    open my $fh, "<", $file or die "$file: $!"; my @lines = <$fh>; close $fh;
    my ($sheet, $sheetLine, $sheetFocused, $sheetEscape) = (undef, 0, 0, 0);
    my $closeSheet = sub {
      report("error", $file, $sheetLine, "sheet without .noInitialFocus()", "struct $sheet") if defined $sheet && !$sheetFocused;
      report("error", $file, $sheetLine, "sheet that Escape does not close (no .cancelAction or .onExitCommand)", "struct $sheet") if defined $sheet && !$sheetEscape;
      $sheet = undef };
    for my $i (0 .. $#lines) {
      my $l = $lines[$i]; my $n = $i + 1;
      if ($l =~ /^(?:private\s+|fileprivate\s+)?struct\s+(\w+Sheet)\s*:\s*View\b/) { $closeSheet->(); ($sheet, $sheetLine, $sheetFocused, $sheetEscape) = ($1, $n, 0, 0) }
      elsif ($l =~ /^(?:private\s+|fileprivate\s+)?(?:struct|final class|class|enum|extension)\s/) { $closeSheet->() }
      $sheetFocused = 1 if defined $sheet && $l =~ /\.noInitialFocus\(\)/;
      $sheetEscape = 1 if defined $sheet && $l =~ /\.cancelAction|\.onExitCommand/;
      next if $l =~ /hig: ok/ || $l =~ /^\s*\/\//;
      report("error", $file, $n, "raw color", $l)
        if $l =~ /\bColor\.(?:white|black|gray|red|green|blue|orange|yellow|pink|purple|teal|mint|cyan|indigo|brown)\b/
        || $l =~ /\bColor\((?:red:|\.sRGB|hue:|white:)/
        || $l =~ /[(:?,]\s*\.(?:white|black|gray|red|green|blue|orange|yellow|pink|purple|teal|mint|cyan|indigo|brown)\b(?!\s*[:=(])/ || $l =~ /\bNSColor\.(?:system\w+|white|black|red|green|blue)\b/;
      report("error", $file, $n, "fixed font size", $l) if $l =~ /\.font\(\.system\(size:/;
      report("error", $file, $n, "literal motion", $l)
        if $l =~ /\.(?:easeIn|easeOut|easeInOut|linear)\(duration:/ || $l =~ /\.(?:spring|bouncy|snappy|smooth)\(/;
      report("error", $file, $n, "glass on content", $l) if $l =~ /\.glassEffect\b/;
      report("error", $file, $n, "unlocalized literal beside String(localized:)", $l)
        if $l =~ /\? "[^"]*[A-Za-z]{3}[^"]*" : String\(localized/ || $l =~ /String\(localized: "[^"]*"\) : "[^"]*[A-Za-z]{3}/;
      if ($l =~ /\.keyboardShortcut\("([a-z])"(?:\s*,\s*modifiers:\s*(?:\.command|\[\s*\.command\s*\]))?\s*\)/ && (my $key = $1) =~ /^[abchimptuvwxz]$/) {
        report("error", $file, $n, "standard shortcut Command-" . uc($key) . " reused", $l) }
      if ($l =~ /\.onTapGesture\b/) {
        my $end = $i + 10 > $#lines ? $#lines : $i + 10;
        my $window = join "", @lines[$i .. $end];
        report("warning", $file, $n, "tap without keyboard path", $l) unless $window =~ /accessibilityAction|hig: ok/ }
    }
    $closeSheet->();
  }
  print "hig-lint: $warnings warnings\n" if $warnings;
  if ($errors) { print "FAIL hig-lint: $errors errors\n"; exit 1 }
  print "PASS hig-lint\n";
' --
