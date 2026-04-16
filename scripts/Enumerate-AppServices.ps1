#Requires -Version 7.0
<#
.SYNOPSIS
    Scans one or more Azure subscriptions for App Services running Node.js
    and emits GitHub Actions output variables suitable for a strategy matrix.

.DESCRIPTION
    Environment variables (all optional — defaults shown):
      SUBSCRIPTION_IDS_INPUT  Comma-separated sub IDs from workflow_dispatch input
                              Leave blank to scan all subscriptions the SP can access
      NODE_STACK_FILTER       Stack prefix to match (default: "NODE")
                               Empty string -> match all App Services (any stack)

    Output (written to $env:GITHUB_OUTPUT when set; printed to stdout otherwise):
      targets  JSON array: [{app_name, resource_group, subscription_id, os_type, node_stack}]
      count    Integer count of discovered targets

    Requires:
      az  (Azure CLI, already logged in before this script is called)
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Log {
    param([string]$Message)
    Write-Host "[enumerate] $Message" -ForegroundColor Cyan
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[enumerate] WARN: $Message" -ForegroundColor Yellow
}

# ── Resolve subscription list ────────────────────────────────────────────────

$rawIds = $env:SUBSCRIPTION_IDS_INPUT

if ([string]::IsNullOrWhiteSpace($rawIds)) {
    Write-Log "No subscription IDs provided via input or secret. Falling back to az account list."
    $rawIds = (az account list --query "[].id" -o tsv 2>$null) -join ','
}

if ([string]::IsNullOrWhiteSpace($rawIds)) {
    Write-Error "[enumerate] ERROR: No Azure subscriptions found. Ensure the service principal has access."
    exit 1
}

$subscriptions = $rawIds -split ',' |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -ne '' }

Write-Log "Scanning $($subscriptions.Count) subscription(s): $($subscriptions -join ', ')"

$stackFilter = if ($null -ne $env:NODE_STACK_FILTER) { $env:NODE_STACK_FILTER } else { 'NODE' }

# ── Enumerate across subscriptions ──────────────────────────────────────────

$targets = [System.Collections.Generic.List[hashtable]]::new()

foreach ($sub in $subscriptions) {
    Write-Log "-> subscription: $sub"

    try {
        az account set --subscription $sub 2>$null | Out-Null
    }
    catch {
        Write-Warn "Cannot access subscription $sub, skipping."
        continue
    }

    $webappsJson = az webapp list `
        --subscription $sub `
        --query "[].{name:name, rg:resourceGroup, kind:kind}" `
        -o json 2>$null

    if (-not $webappsJson) {
        Write-Warn "az webapp list failed for subscription $sub."
        continue
    }

    $webapps = $webappsJson | ConvertFrom-Json
    Write-Log "  Found $($webapps.Count) total App Service(s) in subscription $sub"

    if ($webapps.Count -eq 0) { continue }

    foreach ($app in $webapps) {
        $appName       = $app.name
        $resourceGroup = $app.rg
        $kind          = if ($app.kind) { $app.kind } else { '' }

        # Skip slots, function apps, container apps, logic apps
        if ($kind -match 'functionapp|container|workflow') {
            Write-Log "    Skipping $appName (kind=$kind)"
            continue
        }

        # Fetch site config for stack info
        try {
            $siteConfigJson = az webapp config show `
                --name $appName `
                --resource-group $resourceGroup `
                --subscription $sub `
                -o json 2>$null

            if (-not $siteConfigJson) { throw "Empty response" }
            $siteConfig = $siteConfigJson | ConvertFrom-Json
        }
        catch {
            Write-Warn "Could not fetch config for $appName, skipping."
            continue
        }

        $linuxFx  = if ($siteConfig.linuxFxVersion) { $siteConfig.linuxFxVersion } else { '' }
        $winNode  = if ($siteConfig.nodeVersion)     { $siteConfig.nodeVersion }     else { '' }

        # Determine OS type and stack string
        if ($kind -match 'linux') {
            $osType    = 'Linux'
            $nodeStack = $linuxFx
        }
        else {
            $osType    = 'Windows'
            $nodeStack = $winNode
        }

        # Apply stack filter
        if (-not [string]::IsNullOrEmpty($stackFilter)) {
            if ($nodeStack -notmatch [regex]::Escape($stackFilter)) {
                Write-Log "    Skipping $appName (stack='$nodeStack', filter='$stackFilter')"
                continue
            }
        }

        Write-Log "    MATCH: $appName | rg=$resourceGroup | os=$osType | stack=$nodeStack"

        $targets.Add(@{
            app_name        = $appName
            resource_group  = $resourceGroup
            subscription_id = $sub
            os_type         = $osType
            node_stack      = $nodeStack
        })
    }
}

# ── Emit outputs ─────────────────────────────────────────────────────────────

$targetCount = $targets.Count
Write-Log "Total Node.js App Service targets: $targetCount"

# Convert to JSON array — compact for GitHub Actions, pretty for local runs
$targetsJson = $targets | ConvertTo-Json -Compress -Depth 5

# ConvertTo-Json returns a plain object (not array) when count is 1; force array
if ($targetCount -eq 1) {
    $targetsJson = "[$targetsJson]"
}
elseif ($targetCount -eq 0) {
    $targetsJson = '[]'
}

if ($env:GITHUB_OUTPUT) {
    # GitHub Actions — compact JSON, no newlines (required for matrix)
    Add-Content -Path $env:GITHUB_OUTPUT -Value "targets=$targetsJson"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "count=$targetCount"
}
else {
    # Local run — pretty print
    Write-Host ""
    Write-Host "=== TARGETS ==="
    $targets | ConvertTo-Json -Depth 5 | Write-Host
    Write-Host "=== COUNT: $targetCount ==="
}
