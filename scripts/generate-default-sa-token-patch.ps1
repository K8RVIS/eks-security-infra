param(
  [string]$Overlay = "manifests/overlays/team-a",
  [string]$ServiceAccountFileName = "default-serviceaccount.yaml",
  [string]$PatchFileName = "default-sa-token-patch.yaml"
)

$ErrorActionPreference = "Stop"

function Get-ServiceAccountName {
  param($Doc)

  if ($Doc.kind -eq "CronJob") {
    return $Doc.spec.jobTemplate.spec.template.spec.serviceAccountName
  }

  if ($Doc.kind -eq "Pod") {
    return $Doc.spec.serviceAccountName
  }

  return $Doc.spec.template.spec.serviceAccountName
}

function Get-AutomountValue {
  param($Doc)

  if ($Doc.kind -eq "CronJob") {
    return $Doc.spec.jobTemplate.spec.template.spec.automountServiceAccountToken
  }

  if ($Doc.kind -eq "Pod") {
    return $Doc.spec.automountServiceAccountToken
  }

  if ($Doc.kind -eq "ServiceAccount") {
    return $Doc.automountServiceAccountToken
  }

  return $Doc.spec.template.spec.automountServiceAccountToken
}

function Uses-DefaultServiceAccount {
  param($Doc)

  $sa = Get-ServiceAccountName $Doc
  return [string]::IsNullOrEmpty($sa) -or $sa -eq "default"
}

function Build-PatchDocument {
  param($Doc)

  if ($Doc.kind -eq "CronJob") {
    return [ordered]@{
      apiVersion = $Doc.apiVersion
      kind       = $Doc.kind
      metadata   = [ordered]@{ name = $Doc.metadata.name }
      spec       = [ordered]@{
        jobTemplate = [ordered]@{
          spec = [ordered]@{
            template = [ordered]@{
              spec = [ordered]@{
                automountServiceAccountToken = $false
              }
            }
          }
        }
      }
    }
  }

  if ($Doc.kind -eq "Pod") {
    return [ordered]@{
      apiVersion = $Doc.apiVersion
      kind       = $Doc.kind
      metadata   = [ordered]@{ name = $Doc.metadata.name }
      spec       = [ordered]@{
        automountServiceAccountToken = $false
      }
    }
  }

  return [ordered]@{
    apiVersion = $Doc.apiVersion
    kind       = $Doc.kind
    metadata   = [ordered]@{ name = $Doc.metadata.name }
    spec       = [ordered]@{
      template = [ordered]@{
        spec = [ordered]@{
          automountServiceAccountToken = $false
        }
      }
    }
  }
}

function ConvertTo-YamlSimple {
  param(
    [object]$Value,
    [int]$Indent = 0
  )

  $spaces = " " * $Indent
  $lines = New-Object System.Collections.Generic.List[string]

  foreach ($key in $Value.Keys) {
    $item = $Value[$key]

    if ($item -is [System.Collections.IDictionary]) {
      $lines.Add("${spaces}${key}:")
      foreach ($line in (ConvertTo-YamlSimple -Value $item -Indent ($Indent + 2))) {
        $lines.Add($line)
      }
    } else {
      $rendered = if ($item -is [bool]) { $item.ToString().ToLower() } else { "$item" }
      $lines.Add("${spaces}${key}: $rendered")
    }
  }

  return $lines
}

function Add-KustomizationEntry {
  param(
    [string]$Path,
    [string]$Section,
    [string]$Entry
  )

  $lines = @(Get-Content $Path)

  if ($lines -contains "  - $Entry") {
    return
  }

  $sectionIndex = -1

  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match "^$Section\s*:\s*$") {
      $sectionIndex = $i
      break
    }
  }

  if ($sectionIndex -eq -1) {
    $lines += ""
    $lines += "${Section}:"
    $lines += "  - $Entry"
    Set-Content -Path $Path -Value $lines -Encoding UTF8
    return
  }

  $insertIndex = $lines.Count

  for ($i = $sectionIndex + 1; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match "^[A-Za-z0-9_-]+\s*:") {
      $insertIndex = $i
      break
    }
  }

  $updated = @()

  if ($insertIndex -gt 0) {
    $updated += $lines[0..($insertIndex - 1)]
  }

  $updated += "  - $Entry"

  if ($insertIndex -lt $lines.Count) {
    $updated += $lines[$insertIndex..($lines.Count - 1)]
  }

  Set-Content -Path $Path -Value $updated -Encoding UTF8
}

$overlayPath = Resolve-Path $Overlay
$kustomizationPath = Join-Path $overlayPath "kustomization.yaml"
$serviceAccountPath = Join-Path $overlayPath $ServiceAccountFileName
$patchPath = Join-Path $overlayPath $PatchFileName

if (-not (Test-Path $kustomizationPath)) {
  throw "kustomization.yaml not found: $kustomizationPath"
}

if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
  throw "kubectl is not installed or not in PATH."
}

Write-Host "[1] Render overlay"
$rendered = (kubectl kustomize $overlayPath) -join "`n"

Write-Host "[2] Generate default ServiceAccount resource"
$serviceAccountDoc = [ordered]@{
  apiVersion = "v1"
  kind       = "ServiceAccount"
  metadata   = [ordered]@{ name = "default" }
  automountServiceAccountToken = $false
}

Set-Content -Path $serviceAccountPath -Value (ConvertTo-YamlSimple -Value $serviceAccountDoc) -Encoding UTF8

Write-Host "[3] Parse rendered resources and build workload patches"
$docs = $rendered -split "(?m)^---\s*$"
$patchDocs = New-Object System.Collections.Generic.List[object]
$supportedKinds = @("Pod", "Deployment", "StatefulSet", "DaemonSet", "Job", "CronJob", "ReplicaSet", "ReplicationController")

foreach ($chunk in $docs) {
  $text = $chunk.Trim()

  if ([string]::IsNullOrWhiteSpace($text)) {
    continue
  }

  $json = $text | kubectl create --dry-run=client --validate=false -f - -o json 2>$null


  if (-not $json) {
    continue
  }

  $doc = $json | ConvertFrom-Json

  if ($supportedKinds -notcontains $doc.kind) {
    continue
  }

  if (-not (Uses-DefaultServiceAccount $doc)) {
    Write-Host "Skipping $($doc.kind)/$($doc.metadata.name): non-default ServiceAccount"
    continue
  }

  Write-Host "Adding patch for $($doc.kind)/$($doc.metadata.name)"
  $patchDocs.Add((Build-PatchDocument $doc))
}

Write-Host "[4] Write workload patch file"
$yamlLines = New-Object System.Collections.Generic.List[string]

for ($i = 0; $i -lt $patchDocs.Count; $i++) {
  if ($i -gt 0) {
    $yamlLines.Add("---")
  }

  foreach ($line in (ConvertTo-YamlSimple -Value $patchDocs[$i])) {
    $yamlLines.Add($line)
  }
}

Set-Content -Path $patchPath -Value $yamlLines -Encoding UTF8

Write-Host "[5] Register generated files in kustomization.yaml"
Add-KustomizationEntry -Path $kustomizationPath -Section "resources" -Entry $ServiceAccountFileName
Add-KustomizationEntry -Path $kustomizationPath -Section "patches" -Entry "path: $PatchFileName"

Write-Host "[6] Verify"
$verifyRendered = (kubectl kustomize $overlayPath) -join "`n"
$verifyDocs = $verifyRendered -split "(?m)^---\s*$"
$verifyRows = New-Object System.Collections.Generic.List[object]

foreach ($chunk in $verifyDocs) {
  $text = $chunk.Trim()

  if ([string]::IsNullOrWhiteSpace($text)) {
    continue
  }

  $json = $text | kubectl create --dry-run=client --validate=false -f - -o json 2>$null

  if (-not $json) {
    continue
  }

  $doc = $json | ConvertFrom-Json

  if ($doc.kind -eq "ServiceAccount" -and $doc.metadata.name -eq "default") {
    $automount = Get-AutomountValue $doc
    $verifyRows.Add([PSCustomObject]@{
      Kind        = $doc.kind
      Name        = $doc.metadata.name
      ServiceAcct = "-"
      Automount   = if ($null -eq $automount) { "<unset>" } else { $automount }
      Status      = if ($automount -eq $false) { "OK" } else { "CHECK" }
    })
    continue
  }

  if ($supportedKinds -notcontains $doc.kind) {
    continue
  }

  $sa = Get-ServiceAccountName $doc

  if (-not ([string]::IsNullOrEmpty($sa) -or $sa -eq "default")) {
    continue
  }

  $automount = Get-AutomountValue $doc
  $verifyRows.Add([PSCustomObject]@{
    Kind        = $doc.kind
    Name        = $doc.metadata.name
    ServiceAcct = if ([string]::IsNullOrEmpty($sa)) { "<default>" } else { $sa }
    Automount   = if ($null -eq $automount) { "<unset>" } else { $automount }
    Status      = if ($automount -eq $false) { "OK" } else { "CHECK" }
  })
}

$verifyRows | Sort-Object Kind, Name | Format-Table -AutoSize
