#Authur: Meysam Rajabipour
param (
    [string]$ComputerNameFile = "C:\VM-List.txt"
)

# Graph API authentication details
$AppId = "ApplicationID"
$AppSecret = "Application Secret"
$TenantId = "Azure tenant ID"


# Construct URI for token generation
$uri = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
$body = @{
    client_id     = $AppId
    scope         = "https://graph.microsoft.com/.default"
    client_secret = $AppSecret
    grant_type    = "client_credentials"
}

# Request OAuth token
try {
    $tokenRequest = Invoke-RestMethod -Method Post -Uri $uri -ContentType "application/x-www-form-urlencoded" -Body $body
    $token = $tokenRequest.access_token
} catch {
    Write-Host "Failed to get authentication token: $($_.Exception.Message)" -ForegroundColor Red
    Exit 1
}

# Set Graph API Headers
$Headers = @{
    'Authorization' = "Bearer $token"
    'Content-Type'  = "application/json"
}

# Validate file path
if (-not (Test-Path $ComputerNameFile -PathType Leaf)) {
    Write-Host "The provided file path is invalid or does not exist." -ForegroundColor Red
    Exit 2
}

# Read computer names
$ComputerNames = Get-Content $ComputerNameFile
if (-not $ComputerNames) {
    Write-Host "No computer names found in the file." -ForegroundColor Red
    Exit 2
}

# Set error handling to stop on errors
$ErrorActionPreference = "Stop"

# Service name
$ServiceName = "frxsvc"  #example : FSLogix (Services.msc)
$ServiceStopped = $false  # Flag to track if any service is stopped
$BodyContent = ""
$LineNumber = 1  # Line counter

foreach ($Computer in $ComputerNames) {
    try {
        $WmiQuery = "SELECT * FROM Win32_Service WHERE Name='$ServiceName'"
        Start-Sleep -Seconds 1  # Optional delay for WMI

        $Service = Get-WmiObject -Query $WmiQuery -ComputerName $Computer -ErrorAction Stop
        $ServiceState = if ($Service) { $Service.State } else { "Stopped" }

        if ($ServiceState -eq "Stopped") {
            Write-Host "$LineNumber`t**WARNING:** Your Service is stopped on $Computer." -ForegroundColor Yellow
            $BodyContent += "<p style='color:red;'> $LineNumber : Your Service is <strong>stopped</strong> on: $Computer</p>"
            $ServiceStopped = $true
        } else {
            Write-Host "$LineNumber`t$ServiceName on $Computer is running" -ForegroundColor Green
            $BodyContent += "<p style='color:black;'>$LineNumber : Your Service is <strong>running</strong> on: $Computer</p>"
        }
    } catch {
        Write-Host "Error connecting to $Computer ($($_.Exception.Message))" -ForegroundColor Red
        $BodyContent += "<p style='color:orange;'>$LineNumber : Error connecting to <strong>$Computer</strong>: $($_.Exception.Message)</p>"
    }
    # Increment line number
    $LineNumber++
}

# Email Details
$MsgFrom = "Sender"
$EmailRecipient = "Reciver"
$MsgSubject = "URGENT: Your Email Subject"

# Construct the HTML email body
$htmlBody = @"
<h2> XX Service Status Report</h2>
$BodyContent
"@

# Create the email message with high importance
$MessageParams = @{
    "message" = @{
        "subject" = $MsgSubject
        "importance" = "high"  # Marks email as urgent
        "body"    = @{
            "contentType" = "HTML"
            "content"     = $htmlBody
        }
        "toRecipients" = @(
            @{
                "emailAddress" = @{
                    "address" = $EmailRecipient
                }
            }
        )
    }
}

# Send email if any service is stopped
if ($ServiceStopped) {
    try {
        $sendMailUri = "https://graph.microsoft.com/v1.0/users/$MsgFrom/sendMail"
        $MessageBody = $MessageParams | ConvertTo-Json -Depth 4
        Invoke-RestMethod -Uri $sendMailUri -Headers $Headers -Method POST -Body $MessageBody
        Write-Host "🚨 URGENT ALERT: Email sent to $EmailRecipient 🚨" -ForegroundColor Cyan
    } catch {
        Write-Host "Failed to send email: $($_.Exception.Message)" -ForegroundColor Red
    }
}
