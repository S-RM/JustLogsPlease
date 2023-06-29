
function Get-AADUsers {

    # Get data
    $data = Get-MgUser -All

    # Write data to file
    $data | ForEach-Object {
        Write-ToFile -log $_
    }
}

function Write-ToFile {
    Param(
        [string]$fileName = "AADUsers.json",
        $log
    )

    $jsonString = $log.toJsonString() | ConvertFrom-Json | ConvertTo-Json -Depth 10 -Compress
    Add-Content -Path $filename -Value $jsonString
}

Export-ModuleMember -Function Get-AADUsers