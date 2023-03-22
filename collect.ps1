param (
    [CmdletBinding()]
    # The number of days to look back for logs. Default is 90 days.
    [int]$Lookback = 90,
    # The start date for the log query. Must be specified if EndDate is also specified.
    [string]$StartDate = $null,
    # The end date for the log query. Must be specified if StartDate is also specified.
    [string]$EndDate = $null,
    # The maximum number of results to return from the log query.
    [int]$ResultSize = 1000,
    # A switch to indicate whether to resume from a previous query.
    [switch]$Resume,

    [parameter(Mandatory=$false)]
    [string]$Cert,

    [parameter(Mandatory=$false)]
    [string]$AppID,

    [parameter(Mandatory=$false)]
    [string]$Org

    # Add function key for mongorest api
)

# Import the functions from the functions.ps1 script.
. .\lib\functions.ps1

$AppAuthentication = $false
# Check if any of the required parameters are defined
if ($Cert -or $AppID -or $Org) {
    # Check if all of the required parameters are defined
    if (-not ($Cert -and $AppID -and $Org)) {
        throw "Error: All of the Thumbprint, AppID, and Organization parameters must be defined if any one of them is defined."
    }
    else {
        $AppAuthentication = $true
    }
}


#######################################
### CHECK INPUT PARAMETERS
#######################################

# Check that both StartDate and EndDate are specified, or both are not specified.
if (($StartDate -ne '' -and $EndDate -eq '') -or `
    ($StartDate -eq '' -and $EndDate -ne '')) {
        # Throw an error if the above condition is true.
        throw "Error: StartDate and EndDate must both be specified or both be empty."
}

#######################################
### PARSE INPUT DATES
#######################################

# If specific start and end dates are specified, parse and validate them.
if($StartDate -and $EndDate) {
    # Get date objects from the string inputs.
    $StartDate = Get-DateObjectFromString -Date $StartDate
    $EndDate = Get-DateObjectFromString -Date $EndDate

    # Throw an error if the end date is before or equal to the start date.
    if ($EndDate -le $StartDate) {
        throw "Error: End date must be after start date."
    }
}

# If start and end dates are not specified, use the default lookback value to set them.
if([string]::IsNullOrEmpty($StartDate) -and [string]::IsNullOrEmpty($EndDate)) {
    # Set the start date to the current date minus the lookback value.
    $StartDate = (Get-Date).AddDays(-$Lookback)
    # Set the end date to the current date.
    $EndDate = (Get-Date)
}

#######################################
### INSTALL REQUIRED MODULES
#######################################

# Check if the required PowerShell modules are installed.
$requiredModules = @("ExchangeOnlineManagement", "AzureAD")
# Get the list of missing modules.
$missingModules = $requiredModules | Where-Object { !(Get-Module -Name $_ -ListAvailable) }

# Check if the user has Administrator permissions.
$isAdmin = [bool]([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

# If there are missing modules, install them.
if ($missingModules) {
    # Install the missing modules.
    foreach ($module in $missingModules) {
        Write-Host "Installing module: ${module}"
        # If the user does not have Administrator permissions, use the -CurrentScope parameter.
        if (!$isAdmin) {
            Install-Module -Name $module -Force -Scope CurrentUser
        }
        else {
            Install-Module -Name $module -Force
        }
    }
}

#######################################
### AUTHENTICATE
#######################################

# Setup long running session
$PSO = New-PSSessionOption -IdleTimeout 43200000 # 12 hours

if($AppAuthentication) {
Connect-ExchangeOnline `
    -PSSessionOption $PSO `
    -CertificateThumbPrint $Cert `
    -AppID $AppID `
    -Organization $Org `
    -ShowBanner:$false
}
else {
    Connect-ExchangeOnline -PSSessionOption $PSO -ShowBanner:$false

    # retrieve org value
    $Org = Get-OrganizationConfig | Select-Object -ExpandProperty 'Name'
}

#######################################
### ONBOARD TENANT
#######################################

# TODO: Check if tenant exists, otherwise add. 
# If exists, we are resuming

$filter = @{
    "tenant" = "${Org}"
}
$response = Get-FromMongoDB -collection "tenants" -Filter $filter

if($response.Length -eq 0) {

    # Create tenant record
    $TenantRecord = @{
        Start = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
        End = "" # Undefined yet
        Tenant = "${Org}"
        Status = "Onboarding"
        TotalRecords = ""  # Unknown yet
    }
    $response = Send-ToMongoDB -collection "tenants" -Data $TenantRecord

    # Add ID to record
    $TenantRecord['_id'] = $response.data
}

else {
    $TenantRecord = @{
        _id = $response._id
        Start = $response.Start
        End = $response.End
        Tenant = $response.Tenant
        Status = $response.Status
        TotalRecords = $response.TotalRecords
    }

}


#######################################
### CHUNK TIME PERIODS
#######################################

$TenantRecord['Status'] = "Chunking"
$response = Update-MongoDB -collection "tenants" -Data $TenantRecord 

Get-UALChunks `
    -StartDate $StartDate `
    -EndDate $EndDate `
    -Org $Org `
    -TenantRecord $TenantRecord 

Write-Host ""
Write-Host "#####################################################"
Write-Host "Chunking complete! Starting collection..."
Write-Host "#####################################################"
Write-Host ""

#######################################
### COLLECT LOGS
#######################################

$TenantRecord['Status'] = "Collecting"
$response = Update-MongoDB -collection "tenants" -Data $TenantRecord

# Pull chunks in pages (memory efficient)
$LastId = ""
# Only get uncompleted chunks
$filter = @{
    Status = "Not Started|Processing"
}


try {
    while ($true) {

        # If no next page (first execution)
        if($LastId -eq "") {
            $Chunks = Get-FromMongoDB # Pulls (by server default) first 10 records
        }

        # Else, get next page
        else {
            # Grab next page
            $Chunks = Get-FromMongoDB -Next $LastId # Pulls (by server default) first 10 records
        }
    
        # Is there data?
        if($Chunks.Length -gt 0) {
    
            # Get the last ID, used for next page
            $LastId = ($Chunks[-1])._id
    
             # Proceed with processing
             $Chunks | ForEach-Object {
    
                # Move LogObject to a PSObject
                $LogObject = @{
                    _id = $_._id
                    Tenant = $_.Tenant
                    End = $_.End
                    RecordType = $_.RecordType
                    Start = $_.Start
                    ProcessingStart = $_.ProcessingStart
                    ProcessingEnd = $_.ProcessingEnd
                    RecordCount = $_.RecordCount
                    Status = $_.Status
                }

                # Set status of chunk
                $LogObject['Status'] = "Processing"
                $LogObject['ProcessingStart'] = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
                $response = Update-MongoDB -collection "chunks" -Data $LogObject 
            
                # If there are no records, continue
                if ($LogObject.RecordCount -eq 0) {
                    continue
                }
            
                # Invoke the UAL query
                Write-Host "[INFO] -- Collecting $($LogObject.RecordType) records between $($LogObject.Start) and $($LogObject.End)"
            
                # Create session ID
                $SessionID = [Guid]::NewGuid().ToString()
            
                # Rolling count of records per chunk
                $count = 0
            
                # Set error counter
                $ErrorCounter = 0
                # Delay time when error is hit
                $ErrorDelay = 60
                # Set max errors
                $MaxErrors = 4
                # Error flag
                $ErrorFlag = $false
                # Error message
                $ErrorMessage = ""

                while ($true) {
           
                    ##########################################
                    ### EXECUTE QUERY
                    ##########################################
            
                    # Execute the query
                    $UALResponse = Search-UnifiedAuditLog `
                        -StartDate $($LogObject.Start) `
                        -EndDate $($LogObject.End) `
                        -RecordType $($LogObject.RecordType) `
                        -SessionID $SessionID `
                        -SessionCommand ReturnLargeSet `
                        -Formatted `
                        -ResultSize $ResultSize
            
                    # If we have a valid response
                    if($UALResponse -ne $null) {
            
                        ##########################################
                        ### PROCESS QUERY RESULTS
                        ##########################################
            
                        # Output the total count of record in this time period
                        # Tjis will match the RecordCount of our chunk
                        if($count -eq 0) {
                            $ResultCount = $UALResponse[0].ResultCount
                        }
            
                        # Count the results returned within this iteration
                        # add to rolling total for this period
                        $count += $UALResponse.Count       
                        
                        # Prepare a batch of all records
                        $LogBatch = @()
                        $UALResponse | ForEach-Object {
        
                            # Calculate ID field
                            $LogLine = ($_.AuditData | ConvertFrom-Json -Depth 20)
                            # Not hugely convinced ID is globally unique across all tenants
                            # Hence adding a few additional fields in there to make it very unlikely
                            $id = Get-MD5Hash -String "$($LogLine.Id)$($LogLine.tenant)$($LogLine.CreationTime)$($LogLine.RecordType)$($LogLine.Operation)"
                            
                            # Add id to field
                            $LogLine | Add-Member -MemberType NoteProperty -Name '_id' -Value $id -Force

                            # Add org to field
                            $LogLine | Add-Member -MemberType NoteProperty -Name 'tenant' -Value $Org -Force
        
                            # Add to batch
                            $LogBatch += $LogLine
                        }

                        # Submit to mongo
                        $response = Send-ToMongoDB -collection "records" -Data $LogBatch


                        ##########################################
                        ### CONCLUDE ITERATION
                        ##########################################
            
                        if($count -eq $ResultCount) {
                            Write-Host "[INFO] -- Collected ${count}/${ResultCount} $($LogObject.RecordType) records within time period"
                            # Set status of chunk to complete
                            $LogObject['Status'] = "Complete"
                            $LogObject['ProcessingEnd'] = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
                            $response = Update-MongoDB -collection "chunks" -Data $LogObject 
                            
                            break
                        }

                        elseif ($count -gt $ResultCount) {
                            # This is an error, clear and start again.
                            $ErrorFlag = $true
                            $ErrorMessage = "Too many collected records."
                        }
                    }
            
                    else {

                        # We have returned 0 records. This should not happen, as 
                        # chunks are defined only for periods with > 0 records.

                        # Only solution is to retry the entire period again
                        # Sometimes we can weirdly get MORE records, so do != comparison
                        if($count -ne $LogObject.RecordCount) {
                            # Chunk is incomplete! Definitely error
                            $ErrorFlag = $true
                            $ErrorMessage = "Returned null response."
                        }
                        else {
                            # All is fine, just weird glitch but we have the records.
                            break
                        }
                    }

                    ##########################################
                    ### HANDLE ERRORS
                    ##########################################

                    if($ErrorFlag -eq $true) {

                        if($ErrorCounter -lt $MaxErrors)
                        {
                            Write-Host " [WARN] -- ${ErrorMessage}. Waiting and trying again."

                            # Generate a new session id, and add a delay to loop
                            $SessionID = [Guid]::NewGuid().ToString()
                            $count = 0
                            Start-Sleep -Seconds ($ErrorDelay * ($ErrorCounter + 1))
                            $ErrorCounter += 1

                            # Revert flag
                            $ErrorFlag = $false
                            # Revert message
                            $ErrorMessage = ""

                        }
                        else {
                            # Error counter hit
                            # TODO: Mark chunk as polluted, move on
                            Write-Host " [ERROR] -- Chunk polluted. ${count}/${ResultCount} $($LogObject.RecordType) records collected"                        
                            
                            # Update status of chunk
                            $LogObject['Status'] = "Polluted"
                            $LogObject['ProcessingEnd'] = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
                            $response = Update-MongoDB -collection "chunks" -Data $LogObject 
                            break
                        }    
                    }
                }
            }
        }
    
        # Else, break loop
        else {

            # Update status
            $TenantRecord['Status'] = "Complete"
            $TenantRecord['End'] = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
            $response = Update-MongoDB -collection "tenants" -Data $TenantRecord

            Write-Host ""
            Write-Host "#####################################################"
            Write-Host "################ COLLECTION COMPLETE ################"
            Write-Host "#####################################################"
            Write-Host ""
    
            break
        }
    }
}



finally {
    Disconnect-ExchangeOnline -Confirm:$false
}








