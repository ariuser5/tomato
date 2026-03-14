Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Creates a normalized structured result for script output.
# Params:
# - Status: short status identifier (for example Created, Completed).
# - Message: optional human-readable message.
# - Data: optional extra fields merged into the result object.
# Returns: [pscustomobject] structured output payload.
function New-ToolResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Status,

        [Parameter()]
        [string]$Message,

        [Parameter()]
        [hashtable]$Data
    )

    $result = [ordered]@{
        Status = $Status
    }

    if ($Message) {
        $result.Message = $Message
    }

    if ($Data) {
        foreach ($key in $Data.Keys) {
            $result[$key] = $Data[$key]
        }
    }

    return [pscustomobject]$result
}

Export-ModuleMember -Function New-ToolResult
