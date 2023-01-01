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

$TMPFILENAME = ".\collection.log"
$DATAFILENAME = ".\UnifiedAuditLogs.json"
$CHUNKFILENAME = ".\chunks.json"

$tmpFileExists = Test-Path -Path $TMPFILENAME
$dataFileExists = Test-Path -Path $DATAFILENAME
$chunkFileExists = Test-Path -Path $CHUNKFILENAME

if ($tmpFileExists -or $dataFileExists -or $chunkFileExists) {
    $deletePrompt = "There are existing collection files. Do you want to delete them and start again? [Y/N] "
    $deleteChoice = Read-Host -Prompt $deletePrompt

    if ($deleteChoice -eq "Y" -or $deleteChoice -eq "y") {
        if ($tmpFileExists) {
            Remove-Item -Path $TMPFILENAME -Force | Out-Null
        }
        if ($dataFileExists) {
            Remove-Item -Path $DATAFILENAME -Force | Out-Null
        }
        if ($chunkFileExists) {
            Remove-Item -Path $CHUNKFILENAME -Force | Out-Null
        }
    }
    else {
        Write-Host "Re-run the command using the -Resume flag."
        exit
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
    -Organization $Org -ShowBanner:$false

    Write-Host "Connected to Exchange Online via Azure Application!"

}
else {
    Connect-ExchangeOnline -PSSessionOption $PSO -ShowBanner:$false
    Write-Host "Connected to Exchange Online!"
}


#######################################
### CHUNK TIME PERIODS
#######################################

### If the switch to resume IS NOT set, start new chunk
if(!$Resume) {
    Get-UALChunks -StartDate $StartDate -EndDate $EndDate

    Write-Host ""
    Write-Host "#####################################################"
    Write-Host "Chunking complete! Starting collection..."
    Write-Host "#####################################################"
    Write-Host ""
}

### If the switch is set to resume
else {

    # Check if $TMPFILENAME exists
    if (!(Test-Path -Path $TMPFILENAME)) {
        Write-Output "Error: ${TMPFILENAME} does not exist"
        exit
    }

    # Check if $CHUNKFILENAME exists
    if (!(Test-Path -Path $CHUNKFILENAME)) {
        Write-Output "Error: ${$CHUNKFILENAME} does not exist"
        exit
    }

    # Get last line from tmp
    $lastLine = Get-Content $TMPFILENAME -Tail 1 | ConvertFrom-Json

    $LineNumber = 0

    # Open the file for reading
    $reader = [System.IO.File]::OpenText($CHUNKFILENAME)

    while ($line = $reader.ReadLine()) {
        # Parse the date we want to match
        $line = $line | ConvertFrom-Json
    
        if([datetime]$line.Start -eq $lastLine.Start -and $lastLine.RecordType -eq $line.RecordType) {
            Write-Host "[INFO] -- Found resume point!"
            $LogObject = $lastLine
            break
        }
        # Increment line number
        $LineNumber++
    }
    
    # Close the file when we're done
    $reader.Close()

    if($null -eq $LogObject) {
        Write-Error "Unable to resume operation, please retry without the -Resume flag"
    }
}

#######################################
### SET VARIABLES AND HANDLERS
#######################################

# Open handle to TMP file
$TmpWriter = New-Object System.IO.StreamWriter $TMPFILENAME, $true

# Open the chunk file for reading
$FileStream = [System.IO.File]::Open($CHUNKFILENAME, 'OpenOrCreate', 'ReadWrite')
$StreamReader = New-Object System.IO.StreamReader $FileStream

# Open the data file for writing
$LogWriter = New-Object System.IO.StreamWriter $DATAFILENAME, $true


#######################################
### PREPARE FOR RESUMING IF REQUIRED
#######################################

# TODO: Set variable earlier
if($Resume) {

    # Set resume breaker to track first loop
    $ResumeBreaker = $false

    $lineCounter = 0
    # Seek to the correct position in $CHUNKFILENAME file, as we resume from there
    # Use a loop to read each line in the file
    while (($line = $StreamReader.ReadLine()) -ne $null) {
        if ($lineCounter -eq $lineNumber - 1) {
            # If the counter matches the desired line number, exit the loop
            break
        }
        # Increment the counter
        $lineCounter++
    }

}

# Else, line number is 0
else {
    $LineNumber = 0
}

try {

    # Read lines from the file until the end position is reached
    while (!$StreamReader.EndOfStream) {

        # Read the next line from the file
        $LogLine = $StreamReader.ReadLine()

        # # Parse the JSON from the line
        if($null -ne $LogLine) {

            # If we are resuming, inject the correct start point
            if($Resume -and !$ResumeBreaker) {
                $LogObject = $LogObject
                $ResumeBreaker = $true
            }

            # Otherwise, parse from log
            else {
                $LogObject = ConvertFrom-Json $LogLine
            }

            # If there are no record, continue
            if ($LogObject.RecordCount -eq 0) {
                continue
            }
            
            # Invoke the UAL query
            Write-Host "[INFO] -- Collecting $($LogObject.RecordType) records between $($LogObject.Start) and $($LogObject.End)"

            # Create session ID
            $SessionID = [Guid]::NewGuid().ToString()

            $count = 0

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
                    -SessionCommand ReturnNextPreviewPage `
                    -ResultSize $ResultSize

                # If we have a valid response
                if($UALResponse -ne $null) {

                    ##########################################
                    ### PROCESS QUERY RESULTS
                    ##########################################

                    # Output the total count on the first iteratiion
                    if($count -eq 0) {
                        $ResultCount = $UALResponse[0].ResultCount
                    }

                    # Count the results within this iteration and add to rolling total
                    $count += $UALResponse.Count       
                    
                    # Send the results to file output
                    $UALResponse | ForEach-Object {
                        $LogWriter.WriteLine($_.AuditData)
                    }

                    # Flush cache
                    $LogWriter.Flush()

                    ##########################################
                    ### CONTRUCT TMP FILE LINE
                    ##########################################

                    # Modify the line object with new properties
                    $NewEndDate = $UALResponse[-1].CreationDate

                    # Modify LogObject
                    $NewLogObject = $LogObject
                    $NewLogObject.End = $NewEndDate
                    $NewLogObject.RecordCount = $UALResponse.Count

                    # Write new object file
                    $jsonString = $NewLogObject | ConvertTo-Json
                    $jsonString = $jsonString -replace "`n","" -replace "`r","" -replace "  ", ""

                    $bytes = ([System.Text.Encoding]::UTF8).GetBytes($jsonString)
                    $TmpWriter.WriteLine($bytes, 0, $bytes.Length)

                    ##########################################
                    ### CONCLUDE ITERATION
                    ##########################################

                    if($count -ge $ResultCount) {
                        Write-Host "[INFO] -- Collected ${count}/${ResultCount} $($LogObject.RecordType) records within time period"
                        break
                    }
                }

                else {

                    # Have we completed collection, or are there no logs within time period?
                    if($count -eq 0) {
                        Write-Host "No logs within time period."
                    }

                    else {
                        Write-Host " [INFO] -- Collected ${count}/${ResultCount} $($LogObject.RecordType) records within time period"                        
                    }

                    # Write new object file
                    $jsonString = $LogObject | ConvertTo-Json
                    $jsonString = $jsonString -replace "`n","" -replace "`r","" -replace "  ", ""

                    $bytes = ([System.Text.Encoding]::UTF8).GetBytes($jsonString)
                    $TmpWriter.WriteLine($bytes, 0, $bytes.Length)

                    break
                }
                

            }

            # Track the line number
            $LineNumber += 1
        }     

    }

    Write-Host ""
    Write-Host "#####################################################"
    Write-Host "################ COLLECTION COMPLETE ################"
    Write-Host "#####################################################"
    Write-Host ""

}

finally {

    # Close handles on file
    $TmpWriter.Close()

    # Close the StreamReader and FileStream
    $FileStream.Close()

    # Close the StreamReader and FileStream
    $LogWriter.Close()

    Disconnect-ExchangeOnline -Confirm:$false

}








