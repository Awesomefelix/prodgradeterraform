<#
.SYNOPSIS
    Moves an Azure resource one step up or down a SKU ladder.

.DESCRIPTION
    Started by an Azure Monitor alert (Action Group -> Automation webhook).
    Supported targets:
      Postgres        PostgreSQL Flexible Server. SKUs use Terraform names (B_Standard_B2s, GP_Standard_D4s_v3, MO_...).
      AppServicePlan  App Service plan. SKUs are plan names (P1v3, P2v3, S1, ...).

    Safety rules:
      - Only acts when the alert is "Fired" (ignores "Resolved" notifications).
      - Skips if the resource is not in a Ready state.
      - Skips if the resource was scaled less than CooldownMinutes ago (tracked in a resource tag).
      - Moves exactly one step and never goes beyond either end of the ladder.
      - Skips if the current SKU is not on the ladder.

    Requires the Automation account's system-assigned identity to have Contributor on the target resource.
#>
param(
    [Parameter(Mandatory = $false)]
    [object] $WebhookData,

    [Parameter(Mandatory = $true)]
    [ValidateSet('Postgres', 'AppServicePlan')]
    [string] $TargetType,

    [Parameter(Mandatory = $true)]
    [ValidateSet('Up', 'Down')]
    [string] $Direction,

    [Parameter(Mandatory = $true)]
    [string] $ResourceId,

    [Parameter(Mandatory = $true)]
    [string] $SkuLadderJson,

    [Parameter(Mandatory = $true)]
    [int] $CooldownMinutes
)

$ErrorActionPreference = 'Stop'

$TagLastScaled = 'autoscale-last-scaled-utc'
$TagLastAction = 'autoscale-last-action'
$ApiVersions   = @{ Postgres = '2024-08-01'; AppServicePlan = '2023-12-01' }
$PgPrefix      = @{ Burstable = 'B_'; GeneralPurpose = 'GP_'; MemoryOptimized = 'MO_' }

function Invoke-Arm {
    param([string] $Method, [string] $Path, [string] $Body)
    $params = @{ Method = $Method; Path = $Path }
    if ($Body) { $params['Payload'] = $Body }
    $resp = Invoke-AzRestMethod @params
    if ($resp.StatusCode -lt 200 -or $resp.StatusCode -ge 300) {
        throw "$Method $Path failed ($($resp.StatusCode)): $($resp.Content)"
    }
    return $resp
}

function Get-PgSkuParts([string] $TerraformName) {
    if ($TerraformName -match '^B_(.+)$')  { return @{ Name = $Matches[1]; Tier = 'Burstable' } }
    if ($TerraformName -match '^GP_(.+)$') { return @{ Name = $Matches[1]; Tier = 'GeneralPurpose' } }
    if ($TerraformName -match '^MO_(.+)$') { return @{ Name = $Matches[1]; Tier = 'MemoryOptimized' } }
    throw "Unrecognised PostgreSQL SKU '$TerraformName'. Expected a B_, GP_ or MO_ prefix."
}

function Get-PlanSkuParts([string] $Name) {
    if ($Name -match '^P0v3$')   { return @{ Tier = 'Premium0V3'; Family = 'Pv3' } }
    if ($Name -match '^P\d+v3$') { return @{ Tier = 'PremiumV3';  Family = 'Pv3' } }
    if ($Name -match '^P\d+v2$') { return @{ Tier = 'PremiumV2';  Family = 'Pv2' } }
    if ($Name -match '^S\d$')    { return @{ Tier = 'Standard';   Family = 'S' } }
    if ($Name -match '^B\d$')    { return @{ Tier = 'Basic';      Family = 'B' } }
    throw "Unrecognised App Service plan SKU '$Name'."
}

# 1. Only react to alerts that are firing, not to "Resolved" notifications
if ($WebhookData -and $WebhookData.RequestBody) {
    $alert     = $WebhookData.RequestBody | ConvertFrom-Json
    $condition = $alert.data.essentials.monitorCondition
    if ($condition -and $condition -ne 'Fired') {
        Write-Output "Alert condition is '$condition'. Nothing to do."
        return
    }
    Write-Output ("Triggered by alert '{0}'." -f $alert.data.essentials.alertRule)
}

$null   = Connect-AzAccount -Identity
$ladder = [string[]]($SkuLadderJson | ConvertFrom-Json)
$path   = "${ResourceId}?api-version=$($ApiVersions[$TargetType])"

# 2. Read the current state
$res = (Invoke-Arm -Method GET -Path $path).Content | ConvertFrom-Json

if ($TargetType -eq 'Postgres') {
    $state   = $res.properties.state
    $current = $PgPrefix[[string]$res.sku.tier] + $res.sku.name
}
else {
    $state   = $res.properties.status
    $current = [string]$res.sku.name
}

if ($state -and $state -ne 'Ready') {
    Write-Output "Resource state is '$state', not 'Ready'. Skipping."
    return
}

# 3. Cooldown
$lastText = $null
if ($res.tags -and $res.tags.$TagLastScaled) { $lastText = [string]$res.tags.$TagLastScaled }
if ($lastText) {
    $last    = [datetime]::Parse($lastText, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
    $elapsed = ((Get-Date).ToUniversalTime() - $last.ToUniversalTime()).TotalMinutes
    if ($elapsed -lt $CooldownMinutes) {
        Write-Output ("Scaled {0:N0} minutes ago; cooldown is {1}. Skipping." -f $elapsed, $CooldownMinutes)
        return
    }
}

# 4. Choose the next step on the ladder
$index = [array]::IndexOf($ladder, $current)
if ($index -lt 0) {
    Write-Output "Current SKU '$current' is not on the ladder ($($ladder -join ', ')). Skipping."
    return
}
$targetIndex = if ($Direction -eq 'Up') { $index + 1 } else { $index - 1 }
if ($targetIndex -lt 0 -or $targetIndex -ge $ladder.Count) {
    Write-Output "Already at the $(if ($Direction -eq 'Up') {'top'} else {'bottom'}) of the ladder ($current). Nothing to do."
    return
}
$target = $ladder[$targetIndex]

# 5. Apply
$tags = @{}
if ($res.tags) { $res.tags.PSObject.Properties | ForEach-Object { $tags[$_.Name] = [string]$_.Value } }
$tags[$TagLastScaled] = (Get-Date).ToUniversalTime().ToString('o')
$tags[$TagLastAction] = "$Direction from $current to $target"

if ($TargetType -eq 'Postgres') {
    $parts = Get-PgSkuParts $target
    $body  = @{ sku = @{ name = $parts.Name; tier = $parts.Tier }; tags = $tags } | ConvertTo-Json -Depth 5
    $null  = Invoke-Arm -Method PATCH -Path $path -Body $body
}
else {
    $parts = Get-PlanSkuParts $target
    $res.sku.name   = $target
    $res.sku.size   = $target
    $res.sku.tier   = $parts.Tier
    $res.sku.family = $parts.Family
    $res | Add-Member -NotePropertyName tags -NotePropertyValue $tags -Force
    $null = Invoke-Arm -Method PUT -Path $path -Body ($res | ConvertTo-Json -Depth 20)
}

Write-Output "Scale $Direction accepted: $current -> $target ($TargetType)."
