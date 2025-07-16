 - task: PowerShell@2
      displayName: 'Replace appsettings.json with selected environment file'
      inputs:
        targetType: 'inline'
        script: |
          $config = "$(buildConfiguration)"
          Write-Host " customerName : $(buildConfiguration) "
          $envFile = "appsettings.$config.json"
          $projectDir = "$(Build.SourcesDirectory)/API/ASP.net_core_API"
          $sourcePath = "$projectDir/$envFile"
          $destPath = "$projectDir/appsettings.json"

          if (Test-Path $sourcePath) {
            Copy-Item -Path $sourcePath -Destination $destPath -Force
            Write-Host " Replaced appsettings.json with $envFile"
          } else {
            Write-Error " File $envFile not found!"
            exit 1
          }
    - task: PowerShell@2
      displayName: 'Debug .csproj path'
      inputs:
        targetType: 'inline'
        script: |
          Get-ChildItem -Path "$(Build.SourcesDirectory)/$(projectFolder)" -Filter *.csproj -Recurse
