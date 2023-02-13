$masterSchema = @{}

# Open the input file of JSON lines using StreamReader
$filePath = "C:\Users\Sankgreall\Documents\AzureDevOps\JustLogsPlease\UnifiedAuditLogs.json"
$streamReader = New-Object System.IO.StreamReader($filePath)

# Create a function to recursively process nested object
function processObject([Object]$object, [Object]$master) 
{
    foreach ($property in $object.PsObject.Properties) 
    {
        if ($property.Value -is [System.Collections.Hashtable]) 
        {
            # Check if the property already exists in the master schema
            if (-not $master.ContainsKey($property.Name)) 
            {
                $master.Add($property.Name, @{})
            }

            # Recursively process the nested object
            processObject $property.Value $master[$property.Name]

        }
        
        else 
        {
            if (-not $master.ContainsKey($property.Name))
            {
                # Add the property to the master schema with its value
                $master.Add($property.Name, $property.Value)
            }
        }
    }
    
    return $master
}

# Read the input file of JSON lines line by line
while (($line = $streamReader.ReadLine()) -ne $null) {
    
    # Convert the JSON line to a PowerShell object
    $jsonObject = ConvertFrom-Json -InputObject $line
    
    $masterSchema = processObject $jsonObject $masterSchema
}

# Close the StreamReader
$streamReader.Close()

### Now we have the master schema, perform required processing


# Define key substitutions
$UnderscoreSubstitutions = @(
    "Logon_Type",
    "AzureActiveDirectory_EventType",
    "Client_IPAddress",
    "Event_Data",
    "_ResourceId",
    "Site_",
    "Site_Url",
    "Source_Name",
    "Start_Time"
)

foreach ($sub in $UnderscoreSubstitutions) {

    # Define the original key within our AuditData
    $originalKey = $sub -replace "_", ""

    # If the key is present
    if($masterSchema.ContainsKey($originalKey)) {

        # Define the new key
        $PropertyValue = $masterSchema.$originalKey
        $masterSchema.Add($sub, $PropertyValue)

        # Remove the original key
        $masterSchema.Remove($originalKey)
    }
}

# Add custom properties to align with our log table
$FormattedDate = ($masterSchema.'CreationTime' -As [datetime]).ToString("yyyy-MM-ddTHH:mm:ssZ") # ISO 8601 compliant
$masterSchema.Add("TimeGenerated", (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ"))
$masterSchema.Add("Original_TimeGenerated", $FormattedDate)
$masterSchema.Add("OfficeWorkload", $masterSchema."Workload")

# Remove properties to align with our log table
$masterSchema.Remove("CreationTime")
$masterSchema.Remove("Id")
$masterSchema.Remove("Workload")


# Convert the master schema to a JSON string
$masterSchemaJson = ConvertTo-Json -InputObject $masterSchema -Depth 20 -Compress

# Output the master schema JSON
Write-Output $masterSchemaJson
