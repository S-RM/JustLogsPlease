# Import the functions from the functions.ps1 script.
. .\functions.ps1

function Get-LFRiskySignins {
    param (
        [parameter(mandatory)][string]$output_path
    )
    # User Risks
    # TODO: These cmdlets does not support pagination, meaning there are memory issues
    # with having to pull all possible records in a single request
    # Will have to consider migrating to the REST API 

    # Get all risk detections back
    $risky_user_detections = Get-MgRiskDetection -All

    # Flush to file
    $risky_user_detections | ForEach-Object {
        Write-ToFile -filename "risky.json" -log $_
    }

    # Get high risk user list
    $risky_users = Get-MgRiskyUser -All

    # Flush to file
    $risky_users | ForEach-Object {
        Write-ToFile -filename "risky.json" -log $_
    }

    # Get high risk user history
    $risky_users | ForEach-Object {
        $risky_users_history = Get-MgRiskyUserHistory -RiskyUserId $_.Id -All
        
        # Flush to file
        $risky_users_history | ForEach-Object {
            Write-ToFile -filename "risky.json" -log $_
        }
    }
    
    # SPN risks
    $risky_spn_detections = Get-MgServicePrincipalRiskDetection -All
    
    # Flush to file
    $risky_spn_detections | ForEach-Object {
        Write-ToFile -filename "risky.json" -log $_
    }

    $risky_spns = Get-MgRiskyServicePrincipal -All
    # Flush to file
    $risky_spns | ForEach-Object {
        Write-ToFile -filename "risky.json" -log $_
    }

    $risky_spns | ForEach-Object { 
        $risky_spns_history = Get-MgRiskyServicePrincipalHistory -RiskyServicePrincipalId $_.Id -All
        $risky_spns_history | ForEach-Object {
            Write-ToFile -filename "risky.json" -log $_
        }
    }

    Write-Host "hey"
    
}
Export-ModuleMember -Function Get-LFRiskySignins