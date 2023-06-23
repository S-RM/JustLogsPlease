. .\lib\records.ps1

# Assign the array of record types
$RecordTypes = Get-UALRecordTypes

function Get-MD5Hash($String) {
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $inputBytes = [System.Text.Encoding]::ASCII.GetBytes($String)
    $hashBytes = $md5.ComputeHash($inputBytes)
    $base64String = [System.Convert]::ToBase64String($hashBytes)
    return $base64String
}

function Get-SHA256Hash($String) {
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $inputBytes = [System.Text.Encoding]::UTF8.GetBytes($String)
    $hashBytes = $sha256.ComputeHash($inputBytes)
    $base64String = [System.Convert]::ToBase64String($hashBytes)
    return $base64String
}

function Send-ToMongoDB {
    Param(
        $MongoHost="https://apie3882a5b.azurewebsites.net",
        $collection,
        $operation="PUT",
        $Code="",
        $Data
    )

    $url = "${MongoHost}/api/${collection}?code=${Code}"
    $headers = @{"Content-Type"="application/json"}
    $body = ConvertTo-Json -InputObject $Data -Depth 20

    try {
        $response = Invoke-RestMethod -Uri $url -Method $operation -Headers $headers -Body $body
        return $response
    }
    catch {
        Write-Host "Error sending data to MongoDB: $_"
        return $null
    }
}


function Update-MongoDB {
    Param(
        $MongoHost="https://apie3882a5b.azurewebsites.net",
        $collection,
        $operation="POST",
        $Code="",
        $Data
    )

    $RecordId = $Data['_id']

    # Add an updated timestamp
    $Data['Updated'] = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')

    $url = "${MongoHost}/api/${collection}?code=${Code}&id=${RecordId}"
    $headers = @{"Content-Type"="application/json"}
    $body = ConvertTo-Json -InputObject $Data -Depth 20

    try {
        $response = Invoke-RestMethod -Uri $url -Method $operation -Headers $headers -Body $body
        return $response
    }
    catch {
        Write-Host "Error sending data to MongoDB: $_"
        return $null
    }
}

function Get-FromMongoDB {
    Param(
        $MongoHost="https://apie3882a5b.azurewebsites.net",
        $collection="chunks",
        $operation="GET",
        $Code="",
        $Next = "",
        $Filter = @{}
    )

    # Default params
    $params = "&sort=_id&orderby=asc" # Ensure chunks are processed in order they are created

    # Add next page reference if defined
    if($Next -ne ""){ 
        $params = "${params}&next=${Next}"
    }

    # Add filter if defined
    $filterQuery = ""
    if($Filter.Length -gt 0) {
        $Filter | ForEach-Object {
            $filterQuery = "${filterQuery}&$($_.Key):$($_.Value)"
        }
        
        # Append to params
        $params = "${params}${filterQuery}"
    }

    # Create the URL
    $url = "${MongoHost}/api/list/${collection}?code=${Code}&${params}"
    $headers = @{"Content-Type"="application/json"}

    try {
        $response = Invoke-RestMethod -Uri $url -Method $operation -Headers $headers
        return $response.data
    }
    catch {
        Write-Host "Error reading data to MongoDB: $_"
        return $null
    }
}

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
        [string]$CurrentRecordType="",
        $Org,
        $TenantRecord
    )

    # TODO: Foreach record type up here instead

    ############################################
    # PRE-FLIGHT CHECKS
    ############################################

    Write-Host ""
    Write-Host "#####################################################"
    Write-Host "################ COLLECTING UAL LOGS ################"
    Write-Host "#####################################################"
    Write-Host ""
    Write-Host "Start Date: $($StartDate.ToString('dd/MM/yyyy HH:mm:ss'))"
    Write-Host "End Date: $($EndDate.ToString('dd/MM/yyyy HH:mm:ss'))"
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

    $TenantRecord['TotalRecords'] = $TenantTotalRecords
    $response = Update-MongoDB -collection "tenants" -Data $tenantRecord

    ############################################
    # RECORD TYPE LOOP
    ############################################

    $RecordTypes | ForEach-Object {

        # Reset chunks array
        $Chunks = @()

        # Assign record type to local variable
        $CurrentRecordType = $_

        # Get total records for this type
        $TotalRecords = (Search-UnifiedAuditLog -StartDate $StartDate -EndDate $EndDate -RecordType $CurrentRecordType -ResultSize 1).ResultCount
        
        if($TotalRecords -eq 0) {
            # Next
            return # behaves like continue for ForEach-Object (wtf MS....)
        }
        else {
            Write-Host "[INFO] -- Chunking ${TotalRecords} ${CurrentRecordType} records"
        }
        

        ############################################
        # IF WE CAN, TAKE THE WHOLE TIME PERIOD
        ############################################

        if($TotalRecords -lt $ChunkSize) {

            # Add to our array
            $Chunk = @{
                Status = "Not Started"
                Start = $StartDate.ToString('yyyy-MM-ddTHH:mm:ss')
                End = $EndDate.ToString('yyyy-MM-ddTHH:mm:ss')
                RecordType = $CurrentRecordType
                RecordCount = $TotalRecords
                Tenant = $Org
                ProcessingStart = ""
                ProcessingEnd = ""
            }

            $response = Send-ToMongoDB -collection "chunks" -Data $Chunk
        }

        ############################################
        # OTHERWISE, WE DO CLEVER CHUNKING...
        ############################################

        else
        {
            ### Initiate loop variables
            $IterationModifier = 1
            [datetime]$IterationStart = [datetime]$StartDate
            $BreakFlag = $false
            $ChunkCount = 0
            $PreviousChunk = @{}

            ### Estimate total chunk duration in seconds
            $EstimatedChunkLength = [int]([math]::ceiling($TotalRecords / $ChunkSize))
            $TotalDuration = New-TimeSpan -Start $StartDate -End $EndDate
            $ChunkDuration = ($TotalDuration.TotalSeconds / $EstimatedChunkLength)
            
            ### Begin loop
            while ($true) 
            {
                Write-Host "Iteration Modifier: ${IterationModifier}"

                # Update IterationStart if we have existing chunks
                if($ChunkCount -gt 0) {
                    # Our start is the end of the previous loop
                    [datetime]$IterationStart = [datetime]$PreviousChunk.End
                }

                # Estimate a time period for this iteration
                $IterationDuration = $ChunkDuration * $IterationModifier

                # Calculate predicted end value
                [datetime]$IterationEnd = [datetime]$IterationStart.AddSeconds($IterationDuration)

                # if IterationEnd exceeds EndDate, make them equal and flag break condition
                if($IterationEnd -ge $EndDate) {
                    $IterationEnd = $EndDate
                    $BreakFlag = $true
                }

                if($IterationStart -ge $IterationEnd) {
                    # This should never happen, but if it does its bad
                    Write-Host "[ERROR] -- Iteration state date is greater than or equal to end date"
                    break
                }

                # We have a time period, let's query and get the results
                $IterationRecords = (Search-UnifiedAuditLog -StartDate $IterationStart -EndDate $IterationEnd -RecordType $CurrentRecordType -ResultSize 1).ResultCount

                # If we have too many records, reduce and try again
                if($IterationRecords -gt $ChunkSize) { #  -and $BreakFlag -eq $false

                    # Returned records are too big, we must retry to query with a reduced time period
                    # We use an iteration modifer of 0.5
                    $IterationModifier = $IterationModifier * 0.5
                    continue
                }

                # Otherwise, we have the right amount
                else {

                    # Increase iteration modifier 
                    $IterationModifier = $IterationModifier / 0.8
        
                    # Assume null response means 0
                    if($null -eq $IterationRecords) {
                        $IterationRecords = 0
                    }
        
                    # Add the time period to the array and move on
                    $PreviousChunk = @{
                        Status = "Not Started"
                        Start = $IterationStart.ToString('yyyy-MM-ddTHH:mm:ss')
                        End = $IterationEnd.ToString('yyyy-MM-ddTHH:mm:ss')
                        RecordType = $CurrentRecordType
                        RecordCount = $IterationRecords
                        Tenant = $Org
                        ProcessingStart = ""
                        ProcessingEnd = ""
                    }

                    Write-Host ""
                    Write-Host "[INFO] -- Created chunk between $($IterationStart.ToString('dd/MM/yyyy HH:mm:ss')) and $($IterationEnd.ToString('dd/MM/yyyy HH:mm:ss'))"
                    Write-Host ""

                    ############################################
                    # CLEAN UP LOOP ITERATION
                    ############################################

                    # Send to mongodb
                    $response = Send-ToMongoDB -collection "chunks" -Data $PreviousChunk

                    # Increase chunk count
                    $ChunkCount += 1

                    if($BreakFlag -eq $true) {
                        Write-Host ""
                        Write-Host "[INFO] -- Successfully created $($ChunkCount) chunks for ${CurrentRecordType} records"
                        Write-Host ""
                        break
                    }
                }   
            }
        }
    }

}

