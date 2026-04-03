Write-Host "VariableGroupID $(VariableGroupID)"
          $variableGroup = az pipelines variable-group variable list --group-id $(VariableGroupID) | Convertfrom-Json
          $serviceBusConnStrSecret = "$(serviceBusConnStrSecret)"
          $environmentName = "$(environmentName)"

          $appSettings = Get-Content "$(Pipeline.Workspace)/AppSettings/${{artifact}}.AppSettings.json"
          $expandedValues = $ExecutionContext.InvokeCommand.ExpandString($appSettings)

          $settingsHash = [System.Collections.ArrayList]@()

          $settings = $expandedValues | ConvertFrom-Json
          $settings.AppSettings.PSObject.Properties | ForEach-Object {

            $setting = [PSCustomObject]@{
                name = $_.Name
                slotSetting = $false
                value = $_.Value
              }

            $settingsHash.Add($setting) | Out-Null
          }

          $settingsHash | convertto-json | Set-Content AppSettings.json
          az webapp config appsettings set -g $(ResourceGroupName) -n $(artifactName) --settings '@AppSettings.json'
