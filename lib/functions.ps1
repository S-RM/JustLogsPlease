. .\lib\records.ps1

# Assign the array of record types
$RecordTypes = Get-UALRecordTypes

function Get-DateObjectFromString {

    Param 
    ( 
        [Parameter(mandatory=$true)]
        [string]$DateString
    )

    # Get the time zone information for the user's computer
    $timeZone = Get-TimeZone

    # Get the time zone identifier
    $timeZoneId = $timeZone.Id

    # Use the time zone identifier to determine the correct formatting string for parsing the date
    $formatString = ""

    switch ($timeZoneId) {
        "Eastern Standard Time" {
            # Use the following format string
            $formatString = "MM/dd/yyyy hh:mm:ss"
            break
        }
        "Central Standard Time" {
            # Use the following format string
            $formatString = "MM/dd/yyyy hh:mm:ss"
            break
        }
        "Mountain Standard Time" {
            # Use the following format string
            $formatString = "MM/dd/yyyy hh:mm:ss"
            break
        }
        "Pacific Standard Time" {
            # Use the following format string
            $formatString = "MM/dd/yyyy hh:mm:ss"
            break
        }
        "Alaska Standard Time" {
            # Use the following format string
            $formatString = "MM/dd/yyyy hh:mm:ss"
            break
        }
        "Hawaii-Aleutian Standard Time" {
            # Use the following format string
            $formatString = "MM/dd/yyyy hh:mm:ss"
            break
        }
        default {
            # Use the following format string
            $formatString = "dd/MM/yyyy hh:mm:ss"
            break
        }
    }

    $DateObject = [datetime]::ParseExact($DateString, $formatString, $null)

    return $DateObject

}

#######################################
### IDENTIFY CHUNKS
#######################################

function Get-UALChunks() {

    Param 
    (     
        # Have we identified total records in tenant?
        [int]$TotalRecords=0,
        [int]$MinimumChunks=10,
        [int]$ChunkSize=5000,
        [datetime]$StartDate,
        [datetime]$EndDate,
        $Chunks=@(),
        $IterationCount=0,
        $IterationModifier=1,
        $RecordTypes=$RecordTypes,
        [string]$CurrentRecordType=""
    )

    # TODO: Foreach record type up here instead

    ############################################
    # FUNCTION - FIRST ITERATION CHECK
    ############################################

    <#
        This block captures the very first execution of the function. 
        It 
    #>
    
    # Capture very first iteration
    if($IterationCount -eq 0) {

        Write-Host ""
        Write-Host "#####################################################"
        Write-Host "################ COLLECTING UAL LOGS ################"
        Write-Host "#####################################################"
        Write-Host ""
        Write-Host "Start Date: ${StartDate}"
        Write-Host "End Date: ${EndDate}"
        Write-Host ""
        Write-Host "#####################################################"
        Write-Host ""


        # Count total records for whole estate and check logging is enabled
        $TenantTotalRecords = (Search-UnifiedAuditLog -StartDate $StartDate -EndDate ${EndDate} -ResultSize 1).ResultCount

        if(!($TenantTotalRecords) -or $TenantTotalRecords -lt 1) {
            Write-Host "Error: Logging may not be enabled, unable to identify logs to collect."
            exit
        }

        Write-Host "[INFO] -- Total records across tenancy: ${TenantTotalRecords}"

        # Increase function iteration count
        $IterationCount++

        # Get the record type to process
        $RecordType = $RecordTypes[($IterationCount - 1)]

        # Recurse the function, using the first record type
        return Get-UALChunks -StartDate $StartDate -EndDate $EndDate -IterationCount $IterationCount -CurrentRecordType $RecordType
    }

    ############################################
    # CURRENT RECORD - FIRST ITERATION CHECK
    ############################################

    <#

    #>

    ### Capture first iterations
    if($TotalRecords -lt 1) {
        # Get one log and count the total index
        $TotalRecords = (Search-UnifiedAuditLog -StartDate $StartDate -EndDate $EndDate -RecordType $CurrentRecordType -ResultSize 1).ResultCount
        

        ### There are no records of this record type to collect, move on
        if($TotalRecords -lt 1 -or !($TotalRecords)) {
            # Increase function iteration count
            $IterationCount++

            # Get the next record type to process
            $RecordType = $RecordTypes[($IterationCount - 1)]

            # If there is a next record type
            if($RecordType) {
                # Recurse the function, using the first record type
                return Get-UALChunks -StartDate $StartDate -EndDate $EndDate -IterationCount $IterationCount -CurrentRecordType $RecordType
            }

            # Else, there is not a record type left in the list
            else {
                # End of loop
                return
            }

        }
        else {
            Write-Host "[INFO] -- Chunking ${TotalRecords} ${CurrentRecordType} records"

            # We have total records, recurse the function
            return Get-UALChunks -TotalRecords $TotalRecords -StartDate $StartDate -EndDate $EndDate -IterationCount $IterationCount -CurrentRecordType $CurrentRecordType
        }
    }

    ############################################
    # IF WE CAN, CHUNK INTO EQUAL TIME PERIODS
    ############################################

    <#

    #>

    ### Capture iterations where we have less than the max number of logs
    # First use case is if total records < $ChunkSize, we just carve up the time periods
    if($TotalRecords -lt $ChunkSize) {

        ### We can just divide our time periods to meet the minimum number of chunks

        # Calculate the difference between the start and end in seconds
        $Duration = New-TimeSpan -Start $StartDate -End $EndDate
        $DurationInSeconds = $Duration.TotalSeconds

        # Calculate the duration of each time period in seconds
        $ChunkDurationInSeconds = [int]$DurationInSeconds / $MinimumChunks

        # Calculate the start and end times for each time period
        for ($i = 0; $i -lt $MinimumChunks; $i++) {

            # Chunk start period is start time + chunk duration * $i modifier in loop
            $ChunkPeriodStart = $StartDate + [TimeSpan]::FromSeconds($ChunkDurationInSeconds * $i)

            # Chunk end period is start time + chunk duration * ($i + 1) to equal start of next period
            $ChunkPeriodEnd = $StartDate + [TimeSpan]::FromSeconds($ChunkDurationInSeconds * ($i + 1))

            # TODO: Query each chunk for record count
            $UALResponse = Search-UnifiedAuditLog `
                -StartDate $ChunkPeriodStart `
                -EndDate $ChunkPeriodEnd `
                -RecordType $CurrentRecordType `
                -ResultSize 1

            # If we have a valid response
            if($UALResponse -eq $null) {
                $ChunkRecordCount = 0
            } 
            else {
                $ChunkRecordCount = $UALResponse[0].ResultCount
            }

            # Add to our array
            $Chunks += [PSCustomObject]@{
                Start = $ChunkPeriodStart.ToString('yyyy-MM-ddTHH:mm:ss')
                End = $ChunkPeriodEnd.ToString('yyyy-MM-ddTHH:mm:ss')
                RecordType = $CurrentRecordType
                RecordCount = $ChunkRecordCount
            }
        }

        # Output to file
        $fileName = "chunks.json"
        
        $Chunks | ForEach-Object {
            # If there are records or we don't know the total records
            if($_.RecordCount -ge 0 -or !("RecordCount" -in $_)) {
        
                # Set RecordCount to a false placeholder
                if(!($_.RecordCount -ge 0)) {
                    $_ | Add-Member -NotePropertyName RecordCount -NotePropertyValue $false
                }
                
                $jsonString = $_ | ConvertTo-Json
                $jsonString = $jsonString -replace "`n","" -replace "`r","" -replace "  ", ""
                Add-Content -Path $filename -Value $jsonString
            }
        }

        # Increase function iteration count
        $IterationCount++

        # Get the record type to process
        $RecordType = $RecordTypes[($IterationCount - 1)]

        if($RecordType) {
            # Recurse the function, using the first record type
            return Get-UALChunks -StartDate $StartDate -EndDate $EndDate -IterationCount $IterationCount -CurrentRecordType $RecordType
        }
        else {
            # End of loop
            return
        }

    }

    ############################################
    # OTHERWISE, CALCULATE CHUNK PERIODS
    ############################################

    <#

    #>

    ### Else, we need to validate that each time period has less than $ChunkSize
    # This will involve multiple recursions
    else {

        # Output friendly message on first iteration
        if($Chunks.Length -le 0) {
            Write-Host "[INFO] -- Calculating optimal time collection period for ${CurrentRecordType}, this may take a few minutes"
        }

        Write-Host "Iteration Modifier: ${IterationModifier}"

        # Set break flag to false
        $BreakFlag = $false

        # We start by identifying the correct start time from any
        # previous recursions
        if($Chunks.Length -gt 0) {
            # Our start is the end of the previous loop
            [datetime]$IterationStart = [datetime]$Chunks[-1].End
        }
        else {
            [datetime]$IterationStart = [datetime]$StartDate
        }

        ### Now we have too identify the time period we want to validate
        # We start by calculating approximately how many chunks we will need
        # Minus ones that have already been counted
        $EstimatedChunkLength = [int]($TotalRecords / $ChunkSize)
        if($EstimatedChunkLength -lt 10) {
            $EstimatedChunkLength = 10
        }

        # Account for chunks that have already been processed
        $EstimatedChunkLength = $EstimatedChunkLength - $Chunks.Length
        if($EstimatedChunkLength -lt 1) {
            $EstimatedChunkLength = 1
        }
        
        # Estimate a time period in seconds
        $Duration = New-TimeSpan -Start $IterationStart -End $EndDate
        $DurationInSeconds = ($Duration.TotalSeconds / $EstimatedChunkLength) * $IterationModifier

        # Calculate predicted end value
        [datetime]$IterationEnd = [datetime]$IterationStart.AddSeconds($DurationInSeconds)

        # if IterationEnd exceeds EndDate, make them equal and flag break condition
        if($IterationEnd -ge $EndDate) {
            $IterationEnd = $EndDate
        }

        if($IterationStart -ge $IterationEnd) {
            $BreakFlag = $true
        }


        # We have a time period, let's query and get the results
        $IterationRecords = (Search-UnifiedAuditLog -StartDate $IterationStart -EndDate $IterationEnd -RecordType $CurrentRecordType -ResultSize 1).ResultCount

        if($IterationRecords -ge $ChunkSize -and $BreakFlag -eq $false) {

            # Returned records are too big, we must retry to query with a reduced time period
            # We use an iteration modifer of 0.5
            $IterationModifier = $IterationModifier * 0.5
            
            # Continue the recursion
            return Get-UALChunks -TotalRecords $TotalRecords -IterationModifier $IterationModifier -Chunks $Chunks -StartDate $StartDate -EndDate $EndDate -CurrentRecordType $CurrentRecordType -IterationCount $IterationCount
        }
        else {

            # Revert iteration modifier 
            $IterationModifier = $IterationModifier / 0.8

            if($null -eq $IterationRecords) {
                $IterationRecords = 0
            }

            # Add the time period to the array and move on
            $Chunks += [PSCustomObject]@{
                Start = $IterationStart.ToString('yyyy-MM-ddTHH:mm:ss')
                End = $IterationEnd.ToString('yyyy-MM-ddTHH:mm:ss')
                RecordType = $CurrentRecordType
                RecordCount = $IterationRecords
            }

            if($BreakFlag -eq $false) {
                # Continue the recursion
                return Get-UALChunks -TotalRecords $TotalRecords -IterationModifier $IterationModifier -Chunks $Chunks -StartDate $StartDate -EndDate $EndDate -CurrentRecordType $CurrentRecordType -IterationCount $IterationCount
            }
            else {

                Write-Host "[INFO] -- Successfully created $($Chunks.Length) chunks for ${CurrentRecordType} records"

                # Flush data to file
                # Output to file
                $fileName = "chunks.json"
                
                $Chunks | ForEach-Object {
                    # If there are records or we don't know the total records
                    if($_.RecordCount -ge 0 -or !("RecordCount" -in $_)) {
                
                        # Set RecordCount to a false placeholder
                        if(!($_.RecordCount -ge 0)) {
                            $_ | Add-Member -NotePropertyName RecordCount -NotePropertyValue $false
                        }
                        
                        $jsonString = $_ | ConvertTo-Json
                        $jsonString = $jsonString -replace "`n","" -replace "`r","" -replace "  ", ""
                        Add-Content -Path $filename -Value $jsonString
                    }
                }

                # Move to next record type, else return
                # Increase function iteration count
                $IterationCount++

                # Get the next record type to process
                $RecordType = $RecordTypes[($IterationCount - 1)]

                if($RecordType) {
                    # Recurse the function, using the next record type
                    return Get-UALChunks -StartDate $StartDate -EndDate $EndDate -IterationCount $IterationCount -CurrentRecordType $RecordType
                }
                else {
                    # End of loop
                    return
                }
            }
        }        
    }
}
