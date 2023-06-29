function Get-RiskySignins {

    # Get and write all risk detections
    FetchAndWrite -command {Get-MgRiskDetection}

    # Get and write all risky users and their history
    FetchAndWrite -command {Get-MgRiskyUser} -historyCommand {param($id) Get-MgRiskyUserHistory -RiskyUserId $id} -historyParameterName 'RiskyUserId'

    # Get and write all risky service principals and their history
    FetchAndWrite -command {Get-MgServicePrincipalRiskDetection}
    FetchAndWrite -command {Get-MgRiskyServicePrincipal} -historyCommand {param($id) Get-MgRiskyServicePrincipalHistory -RiskyServicePrincipalId $id} -historyParameterName 'RiskyServicePrincipalId'
}

function FetchAndWrite {
    param (
        [scriptblock]$command,
        [string]$fileName,
        [scriptblock]$historyCommand = $null,
        [string]$historyParameterName = $null
    )

    # Get data
    $data = & $command -All

    # Write data to file
    $data | ForEach-Object {
        Write-ToFile -log $_
    }

    # If there is a history command, get and write history
    if ($historyCommand -ne $null -and $historyParameterName -ne $null) {
        $data | ForEach-Object {
            $history = & $historyCommand $_.Id -All
            $history | ForEach-Object {
                Write-ToFile -log $_
            }
        }
    }
}

function Write-ToFile {
    Param(
        $filename = "AADRiskyLogons.json",
        $log
    )

    $jsonString = $log | ConvertTo-Json -Compress -Depth 10
    Add-Content -Path $filename -Value $jsonString
}
Export-ModuleMember -Function Get-RiskySignins
