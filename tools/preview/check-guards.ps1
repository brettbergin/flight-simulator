#Requires -Version 7.0
$ErrorActionPreference='Stop'
# Extract the actual predicates used by both process guards; do not copy a test
# regex that could pass while a production guard drifts. These singular/plural
# messages are the known Godot shutdown warnings covered by renderer review.
foreach($name in @('run.ps1','launch.ps1')){
 $tokens=$null;$errors=$null
 $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $name),[ref]$tokens,[ref]$errors)
 if($errors.Count){throw "Invalid PowerShell source: $name"}
 $matches=@($ast.FindAll({param($node)
  $node -is [Management.Automation.Language.BinaryExpressionAst] -and
  $node.Operator -eq [Management.Automation.Language.TokenKind]::Imatch -and
  $node.Right -is [Management.Automation.Language.StringConstantExpressionAst] -and
  $node.Right.Value.Contains('ObjectDB')
 },$true))
 if($matches.Count -ne 1){throw "Expected one actual process guard in $name"}
 $pattern=$matches[0].Right.Value
 foreach($warning in @(
  'WARNING: 1 ObjectDB instance was leaked at exit',
  'WARNING: 2 ObjectDB instances were leaked at exit',
  'WARNING: ObjectDB instance leaked at exit',
  'WARNING: ObjectDB instances leaked at exit',
  'ERROR: fixture failure','SCRIPT ERROR: fixture parse failure','FATAL: fixture native failure'
 )){if($warning -notmatch $pattern){throw "$name accepted known failure: $warning"}}
 if('AIRBORNE_PREVIEW_SMOKE {"passed":true,"failures":[]}' -match $pattern){throw "$name rejects a clean positive marker"}
}
Write-Output 'Preview actual guard negative controls passed (both helpers, known singular/plural shutdown warnings).'
