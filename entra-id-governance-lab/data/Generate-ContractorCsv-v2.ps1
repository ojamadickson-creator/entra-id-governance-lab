<#
.SYNOPSIS
    Generates and prepares the contractor CSV source files for Microsoft Entra ID onboarding.

.DESCRIPTION
    Creates the 'data' directory if missing, writes your exact 20 custom contractor identities 
    into 'data/contractors.sample.csv', and copies it to 'data/contractors.csv'.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Ensure the 'data' directory exists
$dataDir = ".\data"
if (-not (Test-Path $dataDir)) {
    New-Item -ItemType Directory -Path $dataDir | Out-Null
    Write-Host "Created 'data' directory." -ForegroundColor Green
}

# Define the path for the sample and working CSV files
$samplePath = Join-Path $dataDir "contractors.sample.csv"
$csvPath = Join-Path $dataDir "contractors.csv"

# Define your exact custom contractor dataset using a here-string
$csvContent = @'
FirstName,LastName,JobTitle,Specialty,Department,CompanyName
Marcus,Reyes,Identity and Access Management Engineer,IAM,Cyber Security Contractors,Beginning Dimension
Aisha,Khan,IM Solutions Architect,IAM,Cyber Security Contractors,Beginning Dimension
Luis,Ferreira,Identity Governance Analyst,IAM,Cyber Security Contractors,Beginning Dimension
Ines,Machado,IM Specialist,IAM,Cyber Security Contractors,Beginning Dimension
Sofia,Santos,SOC Analyst,SOC,Cyber Security Contractors,Beginning Dimension
Diogo,Costa,SOC Analyst,SOC,Cyber Security Contractors,Beginning Dimension
Rui,Gomes,Tier 1 SOC Analyst,SOC,Cyber Security Contractors,Beginning Dimension
Marta,Silva,Tier 1 SOC Analyst,SOC,Cyber Security Contractors,Beginning Dimension
Ana,Lopez,SOC Analyst,SOC,Cyber Security Contractors,Beginning Dimension
Elena,Petrova,Security Operations Lead,SecOps,Cyber Security Contractors,Beginning Dimension
Pedro,Sousa,Security Operations Lead,SecOps,Cyber Security Contractors,Beginning Dimension
Nuno,Ribeiro,Penetration Tester,PenTest,Cyber Security Contractors,Beginning Dimension
Claudia,Mendes,Penetration Tester,PenTest,Cyber Security Contractors,Beginning Dimension
Ivan,Dragov,Penetration Tester,PenTest,Cyber Security Contractors,Beginning Dimension
Miguel,Torres,Cloud Security Engineer,CloudSec,Cyber Security Contractors,Beginning Dimension
Sara,Oliveira,Cloud Security Engineer,CloudSec,Cyber Security Contractors,Beginning Dimension
Dario,Cruz,Cloud App Security Engineer,CloudSec,Cyber Security Contractors,Beginning Dimension
Rita,Marques,Helpdesk Support Engineer,Helpdesk,Cyber Security Contractors,Beginning Dimension
Bruno,Alves,Helpdesk Support Engineer,Helpdesk,Cyber Security Contractors,Beginning Dimension
Nadia,Faro,Helpdesk Support Engineer,Helpdesk,Cyber Security Contractors,Beginning Dimension
'@

# Write the content to the sample file with UTF-8 encoding
$csvContent | Set-Content -Path $samplePath -Encoding utf8
Write-Host "Generated: $samplePath" -ForegroundColor Cyan

# Copy the sample file to the working contractors.csv file
Copy-Item -Path $samplePath -Destination $csvPath -Force
Write-Host "Successfully created and prepared working file: $csvPath with your custom identities!" -ForegroundColor Green
