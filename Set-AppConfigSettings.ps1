function Set-AppConfigSettings {
    param
    (
        $Label = $null,
        $Settings,
        [switch] $JSONContent,
        [switch] $SecretRefs
    )

    if ($Settings.Count -gt 0) {
        if ($Settings.Count -gt 1) {
            # we need to convert the array to a parent json object
            $setting = [PSCustomObject]@{}    
            $Settings | ForEach-Object {
                $setting | Add-Member -NotePropertyName $_.PSObject.Properties.Name -NotePropertyValue $_.PSObject.Properties.Value
            }

            $setting | ConvertTo-Json -Depth 20 | Set-Content temp_AppSettings.json
        }
        else {
            $Settings | ConvertTo-Json -Depth 20 | Set-Content temp_AppSettings.json
        }

        if ($null -eq $label) {
            if ($JSONContent) {
                az appconfig kv import --name $(AppConfigName) --source file --format json --path temp_AppSettings.json --content-type "application/json" --yes
            }
            elseif ($SecretRefs) {
                az appconfig kv import --name $(AppConfigName) --source file --format json --path temp_AppSettings.json --content-type "application/vnd.microsoft.appconfig.keyvaultref+json;charset=utf-8" --yes                
            }
            else {
                az appconfig kv import --name $(AppConfigName) --source file --format json --path temp_AppSettings.json --yes    
            }

        }
        else {
            if ($JSONContent) {
                az appconfig kv import --name $(AppConfigName) --source file --format json --path temp_AppSettings.json --content-type "application/json" --label $label --yes
            }
            elseif ($SecretRefs) {
                az appconfig kv import --name $(AppConfigName) --source file --format json --path temp_AppSettings.json --content-type "application/vnd.microsoft.appconfig.keyvaultref+json;charset=utf-8" --label $label --yes                
            }
            else {
                az appconfig kv import --name $(AppConfigName) --source file --format json --path temp_AppSettings.json --label $label --yes    
            }
        }        
    }
}

# Needs 
# VARIABLEGROUPID
# AppConfigName
# AppConfigIncludedPaths

Write-Host "VariableGroupID $(VARIABLEGROUPID)"
$variableGroup = az pipelines variable-group variable list --group-id $(VARIABLEGROUPID) | Convertfrom-Json

Write-Host $variableGroup

$configFilePath = "$(Pipeline.Workspace)\AppConfig"
$configFiles = Get-ChildItem -Path $configFilePath -File -Recurse
foreach ($configFile in $configFiles) {
    Write-Host "Processing file: $($configFile.FullName)"

    $label = $null
    if ($configFile.Directory.FullName -ne $configFilePath) {
        $label = $configFile.Directory.Name
    }

    # Only add App Config settings from root and any folders specific to environment (comma-separated list in variables)
    $pathsToInclude = "$(AppConfigIncludedPaths)".Split(",")

    if (($label -in $pathsToInclude) -or ($label -eq $null)) {
        Write-Host "Applying label: ($label)"

        # Read in the file
        $settings = Get-Content $($configFile.FullName) -Raw
        $settings = $settings -replace '(?m)(?<=^([^"]|"[^"]*")*)//.*' -replace '(?ms)/\*.*?\*/'
        $expandedValues = $ExecutionContext.InvokeCommand.ExpandString($settings)
    
        # Need to look at each item in json file
        $settingsHash = [System.Collections.ArrayList]@()
        $settingsJSONHash = [System.Collections.ArrayList]@()
        $settingsSecretRefsHash = [System.Collections.ArrayList]@()

        $settings = $expandedValues | ConvertFrom-Json

        if ($settings.PSObject.Properties -eq $null) {
            Write-Host "We should not be here!"
            continue
        }
    
        foreach ($property in $settings.PSObject.Properties) {
            $setting = [PSCustomObject]@{
                $property.Name = $property.Value
            }

            if ($property.TypeNameOfValue -eq 'System.Object[]' -or $property.TypeNameOfValue -eq 'System.Management.Automation.PSCustomObject') {
                # Check to see if $_.Value has a uri property and if so does it have a /secrets/ in it
                if ($property.Value.PSObject.Properties.name -match "uri" -and $property.Value.uri -match "/secrets/") {
                    $settingsSecretRefsHash.Add($setting) | Out-Null
                }
                else {
                    $settingsJSONHash.Add($setting) | Out-Null    
                }
            }
            else {
                $settingsHash.Add($setting) | Out-Null
            }
        }

        Set-AppConfigSettings -Label $label -Settings $settingsHash
        Set-AppConfigSettings -Label $label -Settings $settingsJSONHash -JSONContent
        Set-AppConfigSettings -Label $label -Settings $settingsSecretRefsHash -SecretRefs
    }
    else {
        Write-Host "Label ($label) not permitted for current environment, skipping."
    }
}            

# Delete the variable group afterwards?
# az pipelines variable-group delete --group-id $(VARIABLEGROUPID) --yes