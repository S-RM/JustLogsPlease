function Get-LFRiskySignins {
    param (
        [parameter(mandatory)][string]$output_path
    )
    # User Risks
    $risky_user_detections = Get-MgRiskDetection -All
    $risky_users = Get-MgRiskyUser -All
    $risky_users_history = $risky_users | ForEach-Object {
        Get-MgRiskyUserHistory -RiskyUserId $_.Id -All
    }
    
    # SPN risks
    $risky_spn_detections = Get-MgServicePrincipalRiskDetection -All
    $risky_spns = Get-MgRiskyServicePrincipal -All
    $risky_spns_history = $risky_spns | ForEach-Object { 
        Get-MgRiskyServicePrincipalHistory -RiskyServicePrincipalId $_.Id -All
    }
    
    # Add all to one JSON
    $all_risky = @{
        "user_history" = $risky_users_history
        "users" = $risky_users
        "user_detections" = $risky_user_detections
        "spn_history" = $risky_spn_detections
        "spns" = $risky_spns
        "spn_detections" = $risky_spns_history
    }
    
    $all_risky | ConvertTo-Json | Out-File -Force "$output_path\all_risky.json"
    
}
Export-ModuleMember -Function Get-LFRiskySignins