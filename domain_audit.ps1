<# 
Author Jony Schats - 0xjs
#>

# PLEASE EDIT THESE VARIABLES BEFORE YOU RUN!
$script:PowerView_Path = "$PSScriptRoot\import\PowerView.ps1"
$script:Powerupsql_Path = "$PSScriptRoot\import\PowerUpSQL.ps1"
$script:Impacket_Path = "$PSScriptRoot\import\impacket"
$script:BloodHound_Path = "$PSScriptRoot\import\Sharphound.ps1"
$script:GpRegisteryPolicy_Path = "$PSScriptRoot\import\GPRegistryPolicy\GPRegistryPolicy.psd1"
$script:CME_Path = "$PSScriptRoot\import\cme"
$script:LdapRelayScan_Path = "$PSScriptRoot\import\LdapRelayScan\LdapRelayScan.py"

# Variables
$script:CredentialStatus = ''
$script:OutputDirectory_Path = ''
$script:Findings_Path = ''
$script:Data_Path = ''
$script:Checks_Path = ''
$script:OutputDirectoryCreated = ''
$script:Creds = ''

# Check and Import dependancies
if (-not(Test-Path -Path $PowerView_Path)) {
	Write-Host -ForegroundColor Red "$PowerView_Path Not found on the system"
	Write-Host -ForegroundColor Red "Exiting script most functions use PowerView"
	exit
}
else {
	Import-Module -Force -Name $PowerView_Path -WarningAction silentlycontinue
}

if (-not(Test-Path -Path $BloodHound_Path)) {
	Write-Host -ForegroundColor Red "$BloodHound_Path doesn't exist. Please check the file and path variables in the script."
	Write-Host -ForegroundColor Red "Won't be able to collect BloodHound data"
	Write-Host " "
}
else {
	Import-Module -Force -Name $BloodHound_Path -WarningAction silentlycontinue
}

if (-not(Test-Path -Path $GpRegisteryPolicy_Path)) {
	Write-Host -ForegroundColor Red "$GpRegisteryPolicy_Path doesn't exist. Please check the file and path variables in the script."
	Write-Host -ForegroundColor Red "Won't be able to parse LAPS policy"
	Write-Host " "
}
else {
	Import-Module -Force -Name $GpRegisteryPolicy_Path -WarningAction silentlycontinue
}

if (-not(Test-Path -Path $Impacket_Path\examples\GetUserSPNs.py)) {
	Write-Host -ForegroundColor Red "$Impacket_Path\examples\GetUserSPNs.py doesn't exist. Please check installation."
	Write-Host -ForegroundColor Red "Won't be able to parse Kerberoast, AS-REPRoast or check for the printspooler service"
	Write-Host " "
}

if (-not(Test-Path -Path $LdapRelayScan_Path)) {
	Write-Host -ForegroundColor Red "$LdapRelayScan_Path doesn't exist. Please check installation."
	Write-Host -ForegroundColor Red "Won't be able to check for LDAPS signing and binding"
	Write-Host " "
}

$CheckPython = (python -V)
if (-not($CheckPython -Match "Python")) {
	Write-Host -ForegroundColor Red "Python doesn't exist. Please check installation."
	Write-Host -ForegroundColor Red "Won't be able to do any of the SMB or share checks"
}

if (-not(Test-Path -Path $CME_Path)) {
	Write-Host -ForegroundColor Red "$CME_Path doesn't exist."
	Write-Host -ForegroundColor Red "Won't be able to do any of the SMB or share checks"
}

Function Invoke-ADCheckAll {
<#
.SYNOPSIS
Author: Jony Schats - 0xjs
Required Dependencies: All
Optional Dependencies: None

.DESCRIPTION
<DESCRIPTION>

.PARAMETER Domain
Specifies the domain to use for the query and creating outputdirectory.

.PARAMETER Server
Specifies an Active Directory server IP to bind to, e.g. 10.0.0.1

.PARAMETER User
Specifies the username to use for the query.

.PARAMETER Password
Specifies the Password in combination with the username to use for the query.

.PARAMETER OutputDirectory
Specifies the path to use for the output directory, defaults to the current directory.

.PARAMETER SkipBloodHound
If specified skips the BloodHound enumeration

.PARAMETER SkipRoasting
If specified skips the kerberoasting and AS-REP roasting with Impacket.

.PARAMETER SkipEmptyPasswordGuess
If specified skips authenticating with a empty password for the users with PASSWD_NOTREQD attribute.

.EXAMPLE
Invoke-ADCheckAll -Domain 'contoso.com' -Server 'dc1.contoso.com' -User '0xjs' -Password 'Password01!'
Start ADChecks with all modules
#>

	#Parameters
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory=$true,HelpMessage="Enter a domain name here, e.g. contoso.com")]
		[ValidateNotNullOrEmpty()]
		[string]$Domain,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter a IP of a domain controller here, e.g. 10.0.0.1")]
		[ValidateNotNullOrEmpty()]
		[string]$Server,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter the username to connect with")]
		[ValidateNotNullOrEmpty()]
		[string]$User,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter the password of the user")]
		[ValidateNotNullOrEmpty()]
		[string]$Password,
		
		[Parameter(Mandatory=$false)]
		[ValidateNotNullOrEmpty()]
		[string]$OutputDirectory,
		
		[Parameter(Mandatory = $false)]
		[Switch]
		$SkipBloodHound,
		
		[Parameter(Mandatory = $false)]
		[Switch]
		$SkipRoasting,
		
		[Parameter(Mandatory = $false)]
		[Switch]
		$SkipEmptyPasswordGuess
	)
	
	Write-Verbose "[++] Executing Invoke-ChangeDNS"
	Invoke-ChangeDNS -Domain $Domain -Server $Server
	
	Write-Verbose "[++] Executing Test-ADAuthentication"
	Test-ADAuthentication -Domain $Domain -Server $Server -User $User -Password $Password | Out-Null
	
	if ($User -ne $Creds.Username) {
		Create-CredentialObject -User $User -Password $Password
		
		if ($PSBoundParameters['OutputDirectory']) {
		New-OutputDirectory -Domain $Domain -OutputDirectory $OutputDirectory
		}
		else {
			New-OutputDirectory -Domain $Domain
		}
		
		Write-Host " "
		Invoke-WriteExplanation
		
		if ($SkipBloodHound){
			Invoke-ADEnum -Domain $Domain -Server $Server -User $User -Password $Password -SkipBloodHound
		}
		else {
			Invoke-ADEnum -Domain $Domain -Server $Server -User $User -Password $Password
		}
		
		Invoke-ADEnumTrust -Domain $Domain -Server $Server -User $User -Password $Password
		
		Invoke-ADEnumAzure -Domain $Domain -Server $Server -User $User -Password $Password
		
		Write-Host "---------- EXECUTING CHECKS ----------"
		
		Write-Host "[+] Executing in another window because runas is required"
		Write-Host -ForegroundColor Yellow "[+] Pleace manually supply the Password $Password"
		
		"--- Running SQL checks in new window ---"
		runas /noprofile /env /netonly /user:$Domain\$User "powershell.exe -Exec bypass -NoExit Import-Module $PSCommandPath; Set-Variable Findings_Path -Value $OutputDirectory_Path\findings; Set-Variable Data_Path -Value $OutputDirectory_Path\data; Set-Variable Checks_Path -Value $OutputDirectory_Path\checks; Set-Variable OutputDirectoryCreated -Value $OutputDirectoryCreated; Invoke-ADCheckSQL -Domain $Domain -Server $Server -User $User -Password $Password -SkipPrompt"
		Write-Host " "
		
		Invoke-ADCheckPasspol -Domain $Domain -Server $Server -User $User -Password $Password
		
		Invoke-ADCheckLAPS -Domain $Domain -Server $Server -User $User -Password $Password
		
		Invoke-ADCheckDescription -Domain $Domain -Server $Server -User $User -Password $Password
		
		if ($SkipRoasting){
			Invoke-ADCheckRoasting -Domain $Domain -Server $Server -User $User -Password $Password -SkipRoasting
		}
		else {
			Invoke-ADCheckRoasting -Domain $Domain -Server $Server -User $User -Password $Password
		}
		
		Invoke-ADCheckDelegation -Domain $Domain -Server $Server -User $User -Password $Password
		
		if ($SkipEmptyPasswordGuess){
			Invoke-ADCheckUserAttributes -Domain $Domain -Server $Server -User $User -Password $Password -SkipEmptyPasswordGuess
		}
		else {
			Invoke-ADCheckUserAttributes -Domain $Domain -Server $Server -User $User -Password $Password
		}
		
		Invoke-ADCheckOutdatedComputers -Domain $Domain -Server $Server -User $User -Password $Password

		Invoke-ADCheckInactiveObjects -Domain $Domain -Server $Server -User $User -Password $Password
		
		Invoke-ADCheckPrivilegedObjects -Domain $Domain -Server $Server -User $User -Password $Password

		Invoke-ADCheckDomainJoin -Domain $Domain -Server $Server -User $User -Password $Password
		
		Invoke-ADCheckSysvolPassword -Domain $Domain -Server $Server -User $User -Password $Password
		
		Invoke-ADCheckNetlogonPassword -Domain $Domain -Server $Server -User $User -Password $Password
		
		Invoke-ADCheckPrintspoolerDC -Domain $Domain -Server $Server -User $User -Password $Password
		
		Invoke-ADCheckLDAP -Domain $Domain -Server $Server -User $User -Password $Password
		
		Invoke-ADCheckExchange -Domain $Domain -Server $Server -User $User -Password $Password
		
		Invoke-ADCheckSMB -Domain $Domain -Server $Server -User $User -Password $Password
		
		Invoke-ADCheckWebclient -Domain $Domain -Server $Server -User $User -Password $Password
		
	}
	elseif ($CredentialStatus -eq $false) {
		Write-Host -ForegroundColor Red "[-] Exiting, please provide a valid set op credentials"
	}
}


Function Create-CredentialObject {
<#
.SYNOPSIS
Author: Jony Schats - 0xjs
Required Dependencies: None
Optional Dependencies: None

.DESCRIPTION
Creates a credential object using the username and password supplied.

.PARAMETER User
Specifies the username to use for the query.

.PARAMETER Password
Specifies the Password in combination with the username to use for the query.

.EXAMPLE
Create-CredentialObject -User '0xjs' -Password 'Password01!'
#>	

	#Parameters
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory=$true,HelpMessage="Enter the username to connect with")]
		[ValidateNotNullOrEmpty()]
		[string]$User,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter the password of the user")]
		[ValidateNotNullOrEmpty()]
		[string]$Password
	)

	Write-Verbose "[+] Function Create-CredentialObject"
	$SecurePassword = ConvertTo-SecureString -String $Password -AsPlainText -Force
	$script:Creds = New-Object System.Management.Automation.PSCredential($User, $SecurePassword)
	Write-Verbose "[+] Created credential object with username $User"
}

Function Invoke-ChangeDNS {
<#
.SYNOPSIS
Author: Jony Schats - 0xjs
Required Dependencies: None
Optional Dependencies: None

.DESCRIPTION
Checks if powershell is running as admin and then it changes the DNS for each interface to the one of the domain controller because some checks will fail from a non-domain joined machine perspective if the DC isn't set as the DNS server. It will also add the domain name to the host file, since its required for some checks (impacket).

.PARAMETER Server
Specifies an Active Directory server IP to bind to, e.g. 10.0.0.1

.PARAMETER Domain
Specifies the domain to place with the Server in the hosts file e.g. contoso.com.

.EXAMPLE
Invoke-ChangeDNS -Server '10.0.0.1' -Domain contoso.com
Change DNS Server to 10.0.0.1 and write 10.0.0.1 contoso.com to the hosts file
#>	

	#Parameters
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory=$true,HelpMessage="Enter a domain name here, e.g. contoso.com")]
		[ValidateNotNullOrEmpty()]
		[string]$Domain,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter a IP of a domain controller here, e.g. 10.0.0.1")]
		[ValidateNotNullOrEmpty()]
		[string]$Server
	)
	
	Write-Verbose "[+] Function Invoke-ChangeDNS"
	
	#Check if running as administrator and if yes then change dns and hostfile!
	$id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
	$p = New-Object System.Security.Principal.WindowsPrincipal($id)
	if ($p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)){
		Write-Host "[+] Running as administrator, changing DNS to $Server and adding $Server $Domain to host file "
		Write-Verbose "[+] Running as administrator"
		
		# Set DNS for adapter
		Write-Verbose "[+] Changing DNS for each adapter to DC IP $Server"
		$Array = Get-DnsClientServerAddress
		foreach($element in $Array)
			{
				Set-DnsClientServerAddress -InterfaceIndex $($element).InterfaceIndex -ServerAddresses $Server -ErrorAction silentlycontinue | Out-Null
			} 
		
		#Change host file
		$hostfile_path = "C:\Windows\System32\drivers\etc\hosts"
		$content_hostfile = Get-Content $hostfile_path
		$hostline = "$Server $Domain"
		if ($content_hostfile -match "$hostline"){
				Write-Verbose "[+] $Domain is already in \etc\hosts"
			}
			else {
				Write-Verbose "[+] Writing Domainname $Domain and DC IP $Server to $hostfile_path"
				Add-Content -Path $hostfile_path -Value "`r`n$hostline"
			}
		}     
		else { 
			Write-Host -ForegroundColor Red "[-] Not running as administrator, please manually set hostfile for the domainname and DNS to the DC"
			$confirmation = Read-Host "Did you set the entry in hostfile and changed DN? y/n"
			if ($confirmation -eq 'n') {
			exit
			}
		}
}

Function New-OutputDirectory {
<#
.SYNOPSIS
Author: Jony Schats - 0xjs
Required Dependencies: None
Optional Dependencies: None

.DESCRIPTION
Creates a output directory with the Domainname-Date format and subdirectores for the tool output. Either in the current directory or specified directories.

.PARAMETER Domain
Specifies the domain name to use for the directory name.

.PARAMETER OutputDirectory
Specifies the path to use for the output directory, defaults to the current directory.
#>

	#Parameters
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory=$true,HelpMessage="Enter a domain name here, e.g. contoso.com")]
		[ValidateNotNullOrEmpty()]
		[string]$Domain,
		
		[Parameter(Mandatory=$false)]
		[ValidateNotNullOrEmpty()]
		[string]$OutputDirectory
	)
	Write-Verbose "[+] Function New-OutputDirectory"
	
	#Create a folder with the current date to save data
	$date = (get-date).ToString('yyyy-MM-dd')
	
	if ($PSBoundParameters['OutputDirectory']) {
		Write-Verbose "[+] Setting directory path to $OutputDirectory$domain-$date"
		$script:OutputDirectory_Path = "$OutputDirectory$domain-$date"
	}
	else {
		$OutputDirectory = (get-location)
		Write-Verbose "[+] Defaulting to $OutputDirectory\$domain-$date"
		$script:OutputDirectory_Path = "$OutputDirectory\$domain-$date"
	}
	
	$script:Findings_Path = "$OutputDirectory_Path\findings" 
	$script:Data_Path = "$OutputDirectory_Path\data" 
	$script:Checks_Path = "$OutputDirectory_Path\checks"
	
	if (Test-Path -Path $OutputDirectory_Path) {
	} 
	else {
		New-Item -ItemType Directory -Path "$OutputDirectory_Path" -ErrorAction SilentlyContinue | Out-Null
		Write-Verbose "[+] Created directory $OutputDirectory_Path"
	}
	
	if (Test-Path -Path $Checks_Path) {
	}
	else {
		New-Item -ItemType Directory -Path "$Checks_Path" -ErrorAction SilentlyContinue | Out-Null
		Write-Verbose "[+] Created subdirectory $Checks_Path"
	}
	
	if (Test-Path -Path $Data_Path) {
	}
	else {
		New-Item -ItemType Directory -Path "$Data_Path" -ErrorAction SilentlyContinue | Out-Null
		Write-Verbose "[+] Created subdirectory $Data_Path"
	}
	
	if (Test-Path -Path $Findings_Path) {
	}
	else {
		New-Item -ItemType Directory -Path "$Findings_Path" -ErrorAction SilentlyContinue | Out-Null
		Write-Verbose "[+] Created subdirectory $Findings_Path"
	}
	
	$script:OutputDirectoryCreated = $true
	Write-Host "[+] Output will be written in $OutputDirectory_Path"
}

Function Test-ADAuthentication {
<#
.SYNOPSIS
Author: itpro-tips.com
Required Dependencies: None
Optional Dependencies: None

.DESCRIPTION
Tests a set of credentials against the DC.

.PARAMETER Domain
Specifies the domain to use for the query and creating outputdirectory.

.PARAMETER Server
Specifies an Active Directory server IP to bind to, e.g. 10.0.0.1

.PARAMETER User
Specifies the username to use for the query.

.PARAMETER Password
Specifies the Password in combination with the username to use for the query.

.EXAMPLE 
Test-ADAuthentication -Domain 'contoso.com' -Server 'dc1.contoso.com' -User '0xjs' -Password 'Password01!'
[+] AD Authentication for contoso.com\0xjs succeeded!

.EXAMPLE 
Test-ADAuthentication -Domain 'contoso.com' -Server 'dc1.contoso.com' -User '0xjs' -Password ''
[-] AD Authentication for contoso.com\0xjs failed
#>
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory=$true,HelpMessage="Enter a domain name here, e.g. contoso.com")]
		[ValidateNotNullOrEmpty()]
		[string]$Domain,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter a IP of a domain controller here, e.g. 10.0.0.1")]
		[ValidateNotNullOrEmpty()]
		[string]$Server,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter the username to connect with")]
		[ValidateNotNullOrEmpty()]
		[string]$User,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter the password of the user")]
		[ValidateNotNullOrEmpty()]
		[string]$Password
	)
	
	Write-Verbose "[+] Function Test-ADAuthentication"
	Write-Verbose "[+] Testing credentials $Domain\$User and $Password against $Server"
    Add-Type -AssemblyName System.DirectoryServices.AccountManagement
    
    $contextType = [System.DirectoryServices.AccountManagement.ContextType]::Domain
    
    $argumentList = New-Object -TypeName "System.Collections.ArrayList"
    $null = $argumentList.Add($contextType)
    $null = $argumentList.Add($Domain)
    if($null -ne $Server){
        $argumentList.Add($Server) | Out-Null
    }
    
    $principalContext = New-Object System.DirectoryServices.AccountManagement.PrincipalContext -ArgumentList $argumentList -ErrorAction SilentlyContinue
    if ($null -eq $principalContext) {
        Write-Verbose "[+] Failed authentication to $Server for $Domain\$User"
		Write-Host -ForegroundColor Red "[-] AD Authentication for $Domain\$User failed"
		$script:CredentialStatus = $false
		
    }
    
    if ($principalContext.ValidateCredentials($User, $Password)) {
        Write-Host -ForegroundColor Green "[+] AD Authentication for $Domain\$User succeeded!"
		$script:CredentialStatus = $true
    }
    else {
        Write-Verbose "[+] Failed authentication to $Server for $Domain\$User"
		Write-Host -ForegroundColor Red "[-] AD Authentication for $Domain\$User failed"
		$script:CredentialStatus = $false
    }
}

Function Invoke-WriteExplanation {
<#
.SYNOPSIS
Author: Jony Schats - 0xjs
Required Dependencies: None
Optional Dependencies: None

.DESCRIPTION
Writes the explanation of how the data structure and the output of the tool works.
#>

Write-Host "---------- DATA EXPLAINED ----------"
Write-Host "- All data is written to $OutputDirectory_Path\"
Write-Host "- In this folder are three subfolders"
Write-Host "- files in \findings\ are findings that should be reported"
Write-Host "- files in \checks\ needs to be checked"
Write-Host "- files in \data\ is raw data"
Write-Host " "

Write-Host "---------- COLORS EXPLAINED ----------"
Write-Host "White is informational text"
Write-Host -ForegroundColor DarkGreen "Green means check has passed"
Write-Host -ForegroundColor Yellow "Yellow means manually check the data"
Write-Host -ForegroundColor DarkRed "Dark Red means finding"
Write-Host " "
}

Function Invoke-ADEnum {
<#
.SYNOPSIS
Author: Jony Schats - 0xjs
Required Dependencies: None
Optional Dependencies: None

.DESCRIPTION
Enumerates basic Active Directory stuff like users, groups, computers etc. and saves usefull info in CSV and .txt formats.

.PARAMETER Domain
Specifies the domain to use for the query and creating outputdirectory.

.PARAMETER Server
Specifies an Active Directory server IP to bind to, e.g. 10.0.0.1

.PARAMETER User
Specifies the username to use for the query.

.PARAMETER Password
Specifies the Password in combination with the username to use for the query.

.PARAMETER OutputDirectory
Specifies the path to use for the output directory, defaults to the current directory.

.PARAMETER SkipBloodHound
If specified skips the BloodHound enumeration

.EXAMPLE
Invoke-ADEnum -Domain 'contoso.com' -Server 'dc1.contoso.com' -User '0xjs' -Password 'Password01!'
Execute all enumeration steps

.EXAMPLE
Invoke-ADEnum -Domain 'contoso.com' -Server 'dc1.contoso.com' -User '0xjs' -Password 'Password01!' -OutputDirectory C:\temp\
Execute all basic enumeration steps and save output in C:\temp\

.EXAMPLE
Invoke-ADEnum -Domain 'contoso.com' -Server 'dc1.contoso.com' -User '0xjs' -Password 'Password01!' -SkipBloodHound
Execute all basic enumeration steps but skip BloudHound
#>

	#Parameters
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory=$true,HelpMessage="Enter a domain name here, e.g. contoso.com")]
		[ValidateNotNullOrEmpty()]
		[string]$Domain,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter a IP of a domain controller here, e.g. 10.0.0.1")]
		[ValidateNotNullOrEmpty()]
		[string]$Server,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter the username to connect with")]
		[ValidateNotNullOrEmpty()]
		[string]$User,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter the password of the user")]
		[ValidateNotNullOrEmpty()]
		[string]$Password,
		
		[Parameter(Mandatory=$false)]
		[ValidateNotNullOrEmpty()]
		[string]$OutputDirectory,
		
		[Parameter(Mandatory = $false)]
		[Switch]
		$SkipBloodHound
	)
	
	if ($OutputDirectoryCreated -ne $true) {
		if ($PSBoundParameters['OutputDirectory']) {
			New-OutputDirectory -Domain $Domain -OutputDirectory $OutputDirectory
			}
			else {
				New-OutputDirectory -Domain $Domain
		}
	}
	
	if ($User -ne $Creds.Username) {
		Create-CredentialObject -User $User -Password $Password
	}
	
	Write-Host "---------- GATHERING DATA ----------"
	Write-Host "[+] Gathering data of all Users, Groups, Computerobject, GPO's, OU's, DC's and saving it to csv"
	
	if (-Not $PSBoundParameters['SkipBloodHound']) {
		Write-Host "[+] Gathering BloodHound data all, session and ACL in seperate PowerShell session in background"
		Invoke-Expression "cmd /c start powershell -WindowStyle hidden -Command {Import-Module $script:BloodHound_Path; Invoke-BloodHound -CollectionMethod all -Domain $Domain -DomainController $Server -LdapUsername $User -LdapPassword $Password -OutputDirectory $Data_Path; Invoke-BloodHound -CollectionMethod session -Domain $Domain -DomainController $Server -LdapUsername $User -LdapPassword $Password -OutputDirectory $Data_Path; Invoke-BloodHound -CollectionMethod acl -Domain $Domain -DomainController $Server -LdapUsername $User -LdapPassword $Password -OutputDirectory $Data_Path}"
	}
	
	Write-Verbose "[+] Gathering data of domain object"
	$DomainData = Get-Domain -Domain $Domain -Credential $Creds
	
	Write-Verbose "[+] Gathering data of all Users"
	Get-DomainUser -Domain $Domain -Server $Server -Credential $Creds | Select-Object samaccountname, description, mail, serviceprincipalname, msds-allowedtodelegateto, useraccountcontrol, lastlogon, pwdlastset | Export-Csv $Data_Path\data_users.csv
	
	Write-Verbose "[+] Gathering data of all Groups"
	Get-DomainGroup -Domain $Domain -Server $Server -Credential $Creds | Export-Csv $Data_Path\data_groups.csv
	
	Write-Verbose "[+] Gathering data of all Computerobjects"
	Get-DomainComputer -Domain $Domain -Server $Server -Credential $Creds | Export-Csv $Data_Path\data_computers.csv
	
	Write-Verbose "[+] Gathering data of all GPO's"
	Get-DomainGPO -Domain $Domain -Server $Server -Credential $Creds | Export-Csv $Data_Path\data_gpo.csv
	
	Write-Verbose "[+] Gathering data of all OU's"
	Get-DomainOU -Domain $Domain -Server $Server -Credential $Creds | Export-Csv $Data_Path\data_ou.csv
	
	Write-Verbose "[+] Gathering data of all domain controllers"
	Get-DomainController -Domain $Domain -Server $Server -Credential $Creds | Export-Csv $Data_Path\data_domaincontrollers.csv
	
	#Get the amount of users, groups, computers etc
	$usercount = Import-Csv $Data_Path\data_users.csv | Measure-Object | Select-Object -expand Count
	$usercountenabled = Import-Csv $Data_Path\data_users.csv | Where-Object -Property useraccountcontrol -NotMatch "ACCOUNTDISABLE" | Measure-Object | Select-Object -expand Count
	$groupcount = Import-Csv $Data_Path\data_groups.csv | Measure-Object | Select-Object -expand Count
	$computercount = Import-Csv $Data_Path\data_computers.csv | Measure-Object | Select-Object -expand Count
	$gpocount = Import-Csv $Data_Path\data_gpo.csv | Measure-Object | Select-Object -expand Count
	$oucount = Import-Csv $Data_Path\data_ou.csv | Measure-Object | Select-Object -expand Count
	$dccount = Import-Csv $Data_Path\data_domaincontrollers.csv | Measure-Object | Select-Object -expand Count
	
	Write-Host " "
	
	Write-Host "---------- BASIC ENUMERATION ----------"
	Write-Host "[W] Saving a list of all users to $Data_Path\list_users.txt"
	Import-Csv $Data_Path\data_users.csv | Select-Object -ExpandProperty samaccountname | Sort-Object -Property samaccountname | Out-File $Data_Path\list_users.txt
	Write-Host "[W] Saving a list of all enabled users to $Data_Path\list_users_enabled.txt"
	Import-Csv $Data_Path\data_users.csv | Where-Object -Property useraccountcontrol -NotMatch "ACCOUNTDISABLE" | Select-Object -ExpandProperty samaccountname | Sort-Object -Property samaccountname | Out-File $Data_Path\list_users_enabled.txt
	
	$file = "$Data_Path\list_administrators.txt"
	Write-Host "[W] Saving a list of all administrators to $file"
	$data = Get-DomainGroupMember -Domain $Domain -Server $Server -Credential $Creds "Domain Admins" -Recurse | Get-DomainUser -Domain $Domain -Server $Server -Credential $Creds | Select-Object samaccountname | Format-Table -Autosize 
	$data += Get-DomainGroupMember -Domain $Domain -Server $Server -Credential $Creds "Enterprise Admins" -Recurse | Get-DomainUser -Domain $Domain -Server $Server -Credential $Creds | Select-Object samaccountname | Format-Table -Autosize 
	$data += Get-DomainGroupMember -Domain $Domain -Server $Server -Credential $Creds "Administrators"  -Recurse | Get-DomainUser -Domain $Domain -Server $Server -Credential $Creds | Select-Object samaccountname | Format-Table -Autosize 
	$data | Out-File $file
	$data = Get-Content $file
	$data = $data | Sort-Object -Unique 
	$data = $data -replace 'samaccountname', '' -replace '-', '' -replace 'serviceprincipalname', '' #remove strings
	$data = $data.Trim() | ? {$_.trim() -ne "" } #Remove spaces and white lines
	$data = $data | Sort-Object -Unique
	$data | Out-File $file
	
	Write-Host "[W] Saving a list of all groups to $Data_Path\list_groups.txt"
	Import-Csv $Data_Path\data_groups.csv | Select-Object samaccountname | Sort-Object -Property samaccountname | Out-File $Data_Path\list_groups.txt
	
	Write-Host "[W] Saving a list of all computerobjects to $Data_Path\list_computers.txt"
	Import-Csv $Data_Path\data_computers.csv | Select-Object dnshostname | Sort-Object -Property dnshostname | Out-File $Data_Path\list_computers.txt
	Write-Host " "
	
	# Check if the amount of admins is more then 5% of all users
	$data = Get-Content $data_path\list_administrators.txt | sort-object -Unique
	$admincount = $data | Measure-object | Select-Object -expand Count
	$file = "$findings_path\large_amount_of_administrators.txt"
	$percentage = ($admincount / $usercount ) * 100
	$percentage_admins = [math]::Round($percentage,2)
	$thresholdpercentage = 5
	
	# Defining domain functional levels
	$DomainMode = @{
		0 = "Windows 2000 native"
		1 = "Windows 2003 interim"
		2 = "Windows 2003"
		3 = "Windows 2008"
		4 = "Windows 2008 R2"
		5 = "Windows 2012"
		6 = "Windows 2012 R2"
		7 = "Windows 2016"
		8 = "TBD"
	}
	$DomainFunctionalLevel = $DomainMode[$DomainData.DomainModeLevel]
	
	Write-Host "---------- DOMAIN INFORMATION ----------"
	Write-Host "The domain functional level is: $DomainFunctionalLevel"
	Write-Host "In the domain $Domain there are:" 
	Write-Host "- $usercount users and $usercountenabled enabled users"
	Write-Host "- $groupcount groups"
	Write-Host "- $computercount computers"
	Write-Host "- $oucount OU's"
	Write-Host "- $gpocount GPO's"
	Write-Host "- $admincount Administrators"
	Write-Host "- $dccount Domain Controllers"
	Write-Host " "
	
	# Check if the amount of admins is more then 5% of all users
	Write-Host "---Checking if amount of admins is more then 5% of all users---"
	if ($percentage_admins -lt $thresholdpercentage){ 
		Write-Host -ForegroundColor DarkGreen "[+] There are only $admincount administrators, which is $percentage_admins% of all users"
	}
	else {
		$count = $data | Measure-Object | Select-Object -expand Count
		Write-Host -ForegroundColor Red "[-] There are $admincount administrators, which is $percentage_admins% of all users"
		Write-Host "[W] Writing to $file"
		$data | Out-File $file
	}
	
	Write-Host " "
}

Function Invoke-ADEnumTrust {
<#
.SYNOPSIS
Author: Jony Schats - 0xjs
Required Dependencies: None
Optional Dependencies: None

.DESCRIPTION
Enumerates trusts of the current domain and tries to enumerate trusts of trusted domains within the same forest.

.PARAMETER Domain
Specifies the domain to use for the query and creating outputdirectory.

.PARAMETER Server
Specifies an Active Directory server IP to bind to, e.g. 10.0.0.1

.PARAMETER User
Specifies the username to use for the query.

.PARAMETER Password
Specifies the Password in combination with the username to use for the query.

.PARAMETER OutputDirectory
Specifies the path to use for the output directory, defaults to the current directory.

.EXAMPLE
Invoke-ADEnumTrust -Domain 'contoso.com' -Server 'dc1.contoso.com' -User '0xjs' -Password 'Password01!'
Enumerate trusts for contoso.com

.EXAMPLE
Invoke-ADEnumTrust -Domain 'contoso.com' -Server 'dc1.contoso.com' -User '0xjs' -Password 'Password01!' -OutputDirectory C:\temp\
Enumerate trusts for contoso.com and save output in C:\temp\
#>

	#Parameters
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory=$true,HelpMessage="Enter a domain name here, e.g. contoso.com")]
		[ValidateNotNullOrEmpty()]
		[string]$Domain,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter a IP of a domain controller here, e.g. 10.0.0.1")]
		[ValidateNotNullOrEmpty()]
		[string]$Server,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter the username to connect with")]
		[ValidateNotNullOrEmpty()]
		[string]$User,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter the password of the user")]
		[ValidateNotNullOrEmpty()]
		[string]$Password,
		
		[Parameter(Mandatory=$false)]
		[ValidateNotNullOrEmpty()]
		[string]$OutputDirectory
	)
	
	if ($OutputDirectoryCreated -ne $true) {
		if ($PSBoundParameters['OutputDirectory']) {
			New-OutputDirectory -Domain $Domain -OutputDirectory $OutputDirectory
			}
			else {
				New-OutputDirectory -Domain $Domain
		}
	}
	
	if ($User -ne $Creds.Username) {
		Create-CredentialObject -User $User -Password $Password
	}	
	
	# Enumerating trusts
	Write-Host "---------- ENUMERATING DOMAIN TRUSTS ----------"
	$data = Get-DomainTrust -Domain $Domain -Server $Server -Credential $Creds -ErrorAction silentlycontinue
	
	if ($data) {
		$count = $data | Measure-Object | Select-Object -expand Count
		$file = "$Data_Path\trusts.txt"
		Write-Host "[+] The domain $Domain trusts $count domains which are:"
		$TrustedDomain = $data.TargetName
		$TrustedDomain
		Write-Host "[W] Writing to $file"
		$data | ft | Out-File $file
		Write-Host " "
		
		ForEach ($Trust in $data) {
			$TrustedDomain = $Trust.TargetName
			if ($Trust.TrustAttributes -Match "WITHIN_FOREST"){
				Write-Host "[+] The trust for domain $TrustedDomain is WITHIN_FOREST, enumerating trusts"
				$data2 = Get-DomainTrust -Domain $TrustedDomain -Server $Server -Credential $Creds -ErrorAction silentlycontinue
				$count = $data2 | Measure-Object | Select-Object -expand Count
				if ($data2) {
					Write-Host "[+] The domain $TrustedDomain trusts $count domains which are:"
					$TrustedDomain2 = $data2.TargetName
					$TrustedDomain2
					Write-Host "[W] Writing to $file"
					$data2 | ft | Out-File $file -Append
				}
				else {
					Write-Host -ForegroundColor Red  "[-] Failed to contact $TrustedDomain, can probably not directly contact domain please manually enumerate trusts"
				}
			}
			else {
				Write-Host -ForegroundColor Yellow  "[-] The trust for domain $TrustedDomain is NOT WITHIN_FOREST, can probably not directly contact domain please manually enumerate trusts"
			}
			Write-Host " "
		}
	}
	else {
		Write-Host -ForegroundColor DarkGreen "[+] The domain $Domain doesn't trust any domains"
		Write-Host " "
	}
}

Function Invoke-ADCheckSQL {
<#
.SYNOPSIS
Author: Jony Schats - 0xjs
Required Dependencies: None
Optional Dependencies: None

.DESCRIPTION
Checks if there are any SQL instances in the domain and then checks if the curent user can access them. It checks if the current user is sysadmin and runs, if the SQL instances have any links and if they are configured as sysadmin. Then it runs Invoke-SQLAudit against the instances.

.PARAMETER Domain
Specifies the domain to use for the query and creating outputdirectory.

.PARAMETER Server
Specifies an Active Directory server IP to bind to, e.g. 10.0.0.1

.PARAMETER User
Specifies the username to use for the query.

.PARAMETER Password
Specifies the Password in combination with the username to use for the query.

.PARAMETER OutputDirectory
Specifies the path to use for the output directory, defaults to the current directory.

.PARAMETER SkipPrompt
If specified skips the prompt asking if the process is started as the user to enumerate with.

.EXAMPLE
Invoke-ADCheckSQL -Domain 'contoso.com' -Server 'dc1.contoso.com' -User '0xjs' -Password 'Password01!'
Start all SQL checks and prompt for confirmation that the process is running in the user context already.

.EXAMPLE
Invoke-ADCheckSQL -Domain 'contoso.com' -Server 'dc1.contoso.com' -User '0xjs' -Password 'Password01!'
Start all SQL checks but skip prompt asking if the process is running as the domain user already.
#>

	#Parameters
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory=$true,HelpMessage="Enter a domain name here, e.g. contoso.com")]
		[ValidateNotNullOrEmpty()]
		[string]$Domain,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter a IP of a domain controller here, e.g. 10.0.0.1")]
		[ValidateNotNullOrEmpty()]
		[string]$Server,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter the username to connect with")]
		[ValidateNotNullOrEmpty()]
		[string]$User,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter the password of the user")]
		[ValidateNotNullOrEmpty()]
		[string]$Password,
		
		[Parameter(Mandatory=$false)]
		[ValidateNotNullOrEmpty()]
		[string]$OutputDirectory,
		
		[Parameter(Mandatory = $false)]
		[Switch]
		$SkipPrompt
	)
	
	if ($OutputDirectoryCreated -ne $true) {
		if ($PSBoundParameters['OutputDirectory']) {
			New-OutputDirectory -Domain $Domain -OutputDirectory $OutputDirectory
			}
			else {
				New-OutputDirectory -Domain $Domain
		}
	}
	
	if ($User -ne $Creds.Username) {
		Create-CredentialObject -User $User -Password $Password
	}	
	
	# A way to skipt the prompt asking if its running in the other user's context
	if ($PSBoundParameters['SkipPrompt']) {
		$confirmation = "y"
	}
	else {
		$confirmation = Read-Host "This command needs to be executed from a runas prompt or running in domain context, is it? y/n"
	}
	
	if ($confirmation -eq 'y') {
		"---------- EXECUTING SQL CHECKS ----------"
		
		Import-Module $PowerView_Path
		. $Powerupsql_Path
		

		Write-Host "---Checking MSSQL instances---"
		$data = Get-DomainComputer -Server $Server -Credential $Creds -Domain $Domain | Where-Object serviceprincipalname -Match MSSQL | Select-Object -ExpandProperty serviceprincipalname | Select-String MSSQL
		$count = $data | Measure-Object | Select-Object -expand Count
		if ($data){ 
			Write-Host "[+] Found $count MSSQL instances"
		
			$TblSQLServerSpns = New-Object -TypeName System.Data.DataTable
			$null = $TblSQLServerSpns.Columns.Add('Instance')
			
			foreach($instance in $data) {
			
				$sqlpart = $instance.line.split('/')[1].split(':')[1]
				
				# Check if the instance is a number and use the relevent delim
				$Value = 0
				if([int32]::TryParse($sqlpart,[ref]$Value)) {
					$sqlinstance = $instance -replace ':', ','
				}
				else { 
					$sqlinstance = $instance -replace ':', '\'
				}
				
				$sqlinstance = $sqlinstance -replace 'MSSQLSvc/', ''
				
				$null = $TblSQLServerSpns.Rows.Add($sqlinstance)
			
			}
			
			# Checking connection to MSSQL instances
			Write-Host "[+] Checking connection to each MSSQL instance"
			$results = ForEach ($sqlserver in $TblSQLServerSpns.Instance){
				Get-SQLConnectionTest -Instance $sqlserver
			}
			$Accessible_SQLServers = $results | Where-Object -Property status -Like Accessible 
			
			
			if ($Accessible_SQLServers){
				# If able to connect to a MSSQL server.
				$file = "$Findings_Path\SQLserver_user_has_access.txt"
				$count = $Accessible_SQLServers | Measure-Object | Select-Object -expand Count
				Write-Host -ForegroundColor Red "[-] The current user can access $count MSSQL instances"
				Write-Host "[W] Writing to $file"
				$results | Out-File $file
				Write-Host " "
				
				# Checking if the user is sysadmin on the instance
				Write-Host "---Checking if the user is sysadmin on the accessible instances---"	
				$accessible_sql = $results | Where-Object -Property status -Like Accessible | Get-SQLServerInfo
				$data = $accessible_sql | Where-Object -Property IsSysadmin -Match Yes
				$file = "$Findings_Path\SQLserver_user_issysadmin.txt"
				if ($data.IsSysadmin -match "Yes"){ 
						$count = $data | Measure-Object | Select-Object -expand Count
						Write-Host -ForegroundColor Red "[-] The current user is sysadmin to $count MSSQL instances"
						Write-Host "[W] Writing to $file"
						$data | Out-File $file
					}
					else {
						Write-Host -ForegroundColor DarkGreen "[+] The current user is not sysdmin to any SQL instances"
					}
				Write-Host " "
						
				# Check SQL Server database links
				Write-Host "---Checking database links for sysadmin security context---"	
				$data = $results | Where-Object -Property status -Like Accessible | Get-SQLServerLinkCrawl | Where-Object -Property  sysadmin -Match 1
				$file = "$Findings_Path\SQLserver_sysadmin_on_links.txt"
				if ($data){ 
						$count = $data | Measure-Object | Select-Object -expand Count
						Write-Host -ForegroundColor Red "[-] There are $count links which run under the security context of a sysadmin user"
						Write-Host "[W] Writing to $file"
						$data | Out-File $file
					}
					else {
						Write-Host -ForegroundColor DarkGreen "[+] There are no links which run under the security context of a sysadmin user"
					}
				Write-Host " "
				
				# Audit SQL instances
				Write-Host "---Running Invoke-SQLAudit on the accessible instances---"
				Write-Host "This might take a while"
				$data = $results | Where-Object -Property status -Like Accessible | Invoke-SQLAudit -ErrorAction silentlycontinue
				$file = "$Findings_Path\SQLserver_sqlaudit.txt"
				if ($data){ 
						$count = $data | Measure-Object | Select-Object -expand Count
						Write-Host -ForegroundColor Red "[-] Invoke-SQLAudit found $count issues"
						Write-Host "[W] Writing to $file"
						$data | Out-File $file
					}
					else {
						Write-Host -ForegroundColor DarkGreen "[+] Invoke-SQLAudit didn't found anything"
					}
				Write-Host " "
			
			}
			else {
			Write-Host -ForegroundColor DarkGreen "[+] The current user can't access any MSSQL instances"	
			}
		}
		else {
			Write-Host -ForegroundColor DarkGreen "[+] There are no SQL instances"
		}
		
	}
	elseif ($confirmation -eq 'n') {
		$confirmation = Read-Host "Do you want to start the runas process with the credentials provided ? y/n"
		if ($confirmation -eq 'y') {
			Write-Host "[+] Executing in another window because runas is required"
			Write-Host -ForegroundColor Yellow "[+] Pleace manually supply the Password $Password"
			runas /noprofile /env /netonly /user:$Domain\$User "powershell.exe -Exec bypass -NoExit Import-Module $PSCommandPath; Set-Variable Findings_Path -Value $OutputDirectory_Path\findings; Set-Variable Data_Path -Value $OutputDirectory_Path\data; Set-Variable Checks_Path -Value $OutputDirectory_Path\checks; Set-Variable OutputDirectoryCreated -Value $OutputDirectoryCreated; Invoke-ADCheckSQL -Domain $Domain -Server $Server -User $User -Password $Password -SkipPrompt"
		}
	}
}

Function Invoke-ADEnumAzure {
<#
.SYNOPSIS
Author: Jony Schats - 0xjs
Required Dependencies: None
Optional Dependencies: None

.DESCRIPTION
Checks if Azure AD user(A user starting with MSOL_ or AAD_) is present in the domain and if a computeraccount with the name AZUREADSSOACC exists within the domain.

.PARAMETER Domain
Specifies the domain to use for the query and creating outputdirectory.

.PARAMETER Server
Specifies an Active Directory server IP to bind to, e.g. 10.0.0.1

.PARAMETER User
Specifies the username to use for the query.

.PARAMETER Password
Specifies the Password in combination with the username to use for the query.

.PARAMETER OutputDirectory
Specifies the path to use for the output directory, defaults to the current directory.

.EXAMPLE
Invoke-ADEnumAzure -Domain 'contoso.com' -Server 'dc1.contoso.com' -User '0xjs' -Password 'Password01!'
#>

	#Parameters
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory=$true,HelpMessage="Enter a domain name here, e.g. contoso.com")]
		[ValidateNotNullOrEmpty()]
		[string]$Domain,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter a IP of a domain controller here, e.g. 10.0.0.1")]
		[ValidateNotNullOrEmpty()]
		[string]$Server,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter the username to connect with")]
		[ValidateNotNullOrEmpty()]
		[string]$User,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter the password of the user")]
		[ValidateNotNullOrEmpty()]
		[string]$Password,
		
		[Parameter(Mandatory=$false)]
		[ValidateNotNullOrEmpty()]
		[string]$OutputDirectory
	)
	
	if ($OutputDirectoryCreated -ne $true) {
		if ($PSBoundParameters['OutputDirectory']) {
			New-OutputDirectory -Domain $Domain -OutputDirectory $OutputDirectory
			}
			else {
				New-OutputDirectory -Domain $Domain
		}
	}
	
	if ($User -ne $Creds.Username) {
		Create-CredentialObject -User $User -Password $Password
	}
	
	Write-Host "---Checking if AzureAD connect is in use---"
	$data = Get-DomainUser -Domain $Domain -Server $Server -Credential $Creds | Where-Object {$_.samaccountname -match "MSOL_" -or $_.samaccountname -match "AAD_"} | select samaccountname, description | ft -wrap
	$file = "$data_path\azure_ad_installed_on.txt"
	if ($data){
			Write-Host -ForegroundColor Yellow "[+] AzureAD connect is installed"
			Write-Host "[W] Writing to $file"
			$data | Out-File $file
		}
		else {
			Write-Host "[+] AzureAD connect is not installed"
		}
	Write-Host " "
	
	Write-Host "---Checking if Azure SSO is in use---"
	$data = Get-DomainComputer -Domain $Domain -Server $Server -Credential $Creds | Where-Object {$_.samaccountname -match "AZUREADSSOACC"} | select samaccountname
	$file = "$data_path\azure_sso_installed_on.txt"
	if ($data){ 	
			Write-Host -ForegroundColor Yellow "[+] Azure SSO is configured"
			Write-Host "[W] Writing to $file"
			$data | Out-File $file
		}
		else {
			Write-Host "[+] Azure SSO is not configured"
		}
	Write-Host " "
}

Function Invoke-ADCheckPasspol {
<#
.SYNOPSIS
Author: Jony Schats - 0xjs
Required Dependencies: None
Optional Dependencies: None

.DESCRIPTION
Check the password and lockout policy for strenght requirements and if cleartextpassword is set to 0.

.PARAMETER Domain
Specifies the domain to use for the query and creating outputdirectory.

.PARAMETER Server
Specifies an Active Directory server IP to bind to, e.g. 10.0.0.1

.PARAMETER User
Specifies the username to use for the query.

.PARAMETER Password
Specifies the Password in combination with the username to use for the query.

.PARAMETER OutputDirectory
Specifies the path to use for the output directory, defaults to the current directory.

.EXAMPLE
Invoke-ADCheckPasspol -Domain 'contoso.com' -Server 'dc1.contoso.com' -User '0xjs' -Password 'Password01!'
#>

	#Parameters
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory=$true,HelpMessage="Enter a domain name here, e.g. contoso.com")]
		[ValidateNotNullOrEmpty()]
		[string]$Domain,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter a IP of a domain controller here, e.g. 10.0.0.1")]
		[ValidateNotNullOrEmpty()]
		[string]$Server,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter the username to connect with")]
		[ValidateNotNullOrEmpty()]
		[string]$User,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter the password of the user")]
		[ValidateNotNullOrEmpty()]
		[string]$Password,
		
		[Parameter(Mandatory=$false)]
		[ValidateNotNullOrEmpty()]
		[string]$OutputDirectory
	)
	
	if ($OutputDirectoryCreated -ne $true) {
		if ($PSBoundParameters['OutputDirectory']) {
			New-OutputDirectory -Domain $Domain -OutputDirectory $OutputDirectory
			}
			else {
				New-OutputDirectory -Domain $Domain
		}
	}
	
	if ($User -ne $Creds.Username) {
		Create-CredentialObject -User $User -Password $Password
	}	
	
	Write-Host "---Checking password policy---"
	$data = Get-DomainPolicyData -Domain $Domain -Server $Server -Credential $Creds
	$file = "$findings_path\passwordpolicy.txt"
	
	# CHECK IF ClearTextPassword=0
	if ($data.systemaccess.ClearTextPassword -as [int] -eq 0){ 
		Write-Host -ForegroundColor DarkGreen "[+] Passwordpolicy contains ClearTextPassword=0. Domain controller doesn't save passwords in cleartext"
	}
	ElseIf ($data.systemaccess.ClearTextPassword -as [int] -eq 1) {
		Write-Host -ForegroundColor Red "[-] Passwordpolicy contains ClearTextPassword=1. Domain Controller saves passwords in cleartext"
		$file = "$findings_path\passwordpolicy_cleartext.txt"
		Write-Host "[W] Writing to $file"
		$data.systemaccess | Out-File "$findings_path\passwordpolicy_ClearTextPassword.txt"
	}
	Else {
		Write-Host -ForegroundColor Yellow "[+] Could not determine cleartextpassword value, please manually check passwordpolicy"
	}
	
	#Check minimun password length
	$MinimumPasswordLength = $data.systemaccess.MinimumPasswordLength
	if ($MinimumPasswordLength -as [int] -ge "12"){
		Write-Host -ForegroundColor DarkGreen "[+] Password length requirement is higher or equal to 12"
	}
	Else {
		Write-Host -ForegroundColor Red "[-] Password length requirement is $MinimumPasswordLength characters"
	}
	
	#Check Password complexity
	if ($data.systemaccess.MinimumPasswordLength -as [int] -eq "1"){
		Write-Host -ForegroundColor DarkGreen "[+] PasswordComplexity is equal to 1 (Enabled)"
	}
	Else {
		Write-Host -ForegroundColor Red "[-] PasswordComplexity is 0 (Disabled)!"
	}
	
	#Checks for account lockout
	$LockoutBadCount = $data.systemaccess.LockoutBadCount
	if ($LockoutBadCount -as [int] -gt "6"){
		Write-Host -ForegroundColor Red "[-] LockOutBadCount is $LockoutBadCount"
	}
	ElseIf ($LockoutBadCount -as [int] -eq 0) {
		Write-Host -ForegroundColor Red "[-] LockOutBadCount is 0, accounts wont be locked!"
	}
	Else {
		Write-Host -ForegroundColor DarkGreen "[+] LockOutBadCount is $LockoutBadCount"
	}
	
	$ResetLockoutCount = $data.systemaccess.ResetLockoutCount
	if ($ResetLockoutCount){	
		if ($ResetLockoutCount -as [int] -ge "30"){
			Write-Host -ForegroundColor DarkGreen "[+] ResetLockoutCount is $ResetLockoutCount"
		}
		Else {
			Write-Host -ForegroundColor Red "[-] ResetLockoutCount is $ResetLockoutCount"
		}
	}
	Else {
		Write-Host -ForegroundColor Red "[-] ResetLockoutCount is not set"	
	}
	
	$LockoutDuration = $data.systemaccess.LockoutDuration
	if ($ResetLockoutCount){
		if ($LockoutDuration -as [int] -ge "30"){
			Write-Host -ForegroundColor DarkGreen "[+] LockoutDuration is $LockoutDuration"
		}
		Else {
			Write-Host -ForegroundColor Red "[-] LockoutDuration is $LockoutDuration"
		}
	}
	Else {
		Write-Host -ForegroundColor Red "[-] LockoutDuration is not set"	
	}
	Write-Host "Writing password policy to $file"
	$data.systemaccess | Out-File $file
	Write-Host " "
}

Function Invoke-ADCheckLAPS {
<#
.SYNOPSIS
Author: Jony Schats - 0xjs
Required Dependencies: None
Optional Dependencies: None

.DESCRIPTION
Checks if LAPS exists in the domain by checking GPO and the ms-Mcs-AdmPwdExpirationTime attribute. If a GPO is found it enumerates the LAPS policy. Then It checks if the current user can read any LAPS passwords.

.PARAMETER Domain
Specifies the domain to use for the query and creating outputdirectory.

.PARAMETER Server
Specifies an Active Directory server IP to bind to, e.g. 10.0.0.1

.PARAMETER User
Specifies the username to use for the query.

.PARAMETER Password
Specifies the Password in combination with the username to use for the query.

.PARAMETER OutputDirectory
Specifies the path to use for the output directory, defaults to the current directory.

.EXAMPLE
Invoke-ADCheckLAPS -Domain 'contoso.com' -Server 'dc1.contoso.com' -User '0xjs' -Password 'Password01!'
#>

	#Parameters
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory=$true,HelpMessage="Enter a domain name here, e.g. contoso.com")]
		[ValidateNotNullOrEmpty()]
		[string]$Domain,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter a IP of a domain controller here, e.g. 10.0.0.1")]
		[ValidateNotNullOrEmpty()]
		[string]$Server,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter the username to connect with")]
		[ValidateNotNullOrEmpty()]
		[string]$User,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter the password of the user")]
		[ValidateNotNullOrEmpty()]
		[string]$Password,
		
		[Parameter(Mandatory=$false)]
		[ValidateNotNullOrEmpty()]
		[string]$OutputDirectory
	)
	
	if ($OutputDirectoryCreated -ne $true) {
		if ($PSBoundParameters['OutputDirectory']) {
			New-OutputDirectory -Domain $Domain -OutputDirectory $OutputDirectory
			}
			else {
				New-OutputDirectory -Domain $Domain
		}
	}
	
	if ($User -ne $Creds.Username) {
		Create-CredentialObject -User $User -Password $Password
	}	

	# Checking LAPS existence + configuration
	# Check if there is a GPO with laps in its name
	Write-Host "---Checking if there is a GPO with LAPS---"
	$data = Get-DomainGPO -Domain $Domain -Server $Server -Credential $Creds -Identity *LAPS* 
	$file = "$data_path\laps_gpo.txt"
	if ($data){ 
			$count = $data | Measure-Object | Select-Object -expand Count
			Write-Host -ForegroundColor DarkGreen "[+] There are $count GPO's with LAPS in their name"
			Write-Host "[W] Writing to $file"
			$data | Out-File $file
			Write-Host " "
			$lapsgpo = 1
			
			# Check to which OU's the GPO's are applied to
			Write-Host "---Checking to which OU's the GPO's are applied to---"
			ForEach ($distinguishedname in $data.distinguishedname){
				$data2 = Get-DomainOU -Domain $Domain -Server $Server -Credential $Creds -GPLink $distinguishedname  | select name, distinguishedname
				if ($data2 -eq $null){ 
						Write-Host -ForegroundColor Red "[-] The GPO isn't linked to any OU"
						Write-Host -ForegroundColor Yellow "[-] Please manually check out"
					}
					else {
						$count = $data2 | Measure-Object | Select-Object -expand Count
						Write-Host -ForegroundColor DarkGreen "[+] The GPO is linked to $count OU's"
						Write-Host -ForegroundColor Yellow "[-] Please manually check which OU's etc."
						$file = "$findings_path\laps_gpo_ou.txt"
						Write-Host "[W] Writing to $file"
						$data2 | Out-File -Append $file
					}
			}
			Write-Host " "
			
			# Check the LAPS policy
			Write-Host "---Checking the LAPS policy for each GPO---"
			
			# Mount drive since from non domain context can't access the DC share.
			$hostname = (Get-Domain -Domain $Domain -Credential $Creds).name
			New-PSDrive -Name LAPS -PSProvider FileSystem -Root \\$hostname\SYSVOL -Credential $Creds | out-null
			
			ForEach ($entry in $data){
				$GPO = $entry.displayname
				$gpcfilesyspath = $entry.gpcfilesyspath
				$data2 = Parse-PolFile "$gpcfilesyspath\Machine\Registry.pol" | select ValueName, ValueData
				if ($data2){ 
						Write-Host "[+] Found LAPS password policy for $GPO"
						$file = "$findings_path\laps_policy.txt"
						Write-Host "[W] Writing to $file"
						echo "$GPO" >> $file
						$data2 | Out-File -Append $file
						
						# Check AdminAccountName
						if (($data2 | Where-Object -Property ValueName -Match AdminAccountName | Select-Object ValueData).ValueData -eq $null){
							Write-Host -ForegroundColor Yellow "[-] The LAPS local admin user is the default administrator account"
						}
						Else {
							Write-Host -ForegroundColor DarkGreen "[+] The LAPS local admin user is not the default administrator account"
						}
						
						# Check PasswordComplexity
						if (($data2 | Where-Object -Property ValueName -Match PasswordComplexity | Select-Object ValueData).ValueData -eq "4"){
							Write-Host -ForegroundColor DarkGreen "[+] The password complexity is 4"
						}
						Else {
							Write-Host -ForegroundColor Red "[-] The password complexity is less then 4"
						}
						
						# Check PasswordLength
						if (($data2 | Where-Object -Property ValueName -Match PasswordLength | Select-Object ValueData).ValueData -eq "14"){
							Write-Host -ForegroundColor Yellow "[+] The password length is the default 14"
						}
						Elseif (($data2 | Where-Object -Property ValueName -Match PasswordLength | Select-Object ValueData).ValueData -lt "14") {
							Write-Host -ForegroundColor Red "[-] The password length is less then 14"
						}
						Elseif (($data2 | Where-Object -Property ValueName -Match PasswordLength | Select-Object ValueData).ValueData -gt "14") {
							Write-Host -ForegroundColor DarkGreen "[+] The password length is longer then 14"
						}
						
						# Check PasswordAgeDays
						if (($data2 | Where-Object -Property ValueName -Match PasswordAgeDays | Select-Object ValueData).ValueData -eq "30"){
							Write-Host -ForegroundColor Yellow "[+] The password age days is the default 30"
						}
						Elseif (($data2 | Where-Object -Property ValueName -Match PasswordAgeDays | Select-Object ValueData).ValueData -lt "30") {
							Write-Host -ForegroundColor DarkGreen "[+] The password age days is less then 30"
						}
						Elseif (($data2 | Where-Object -Property ValueName -Match PasswordAgeDays | Select-Object ValueData).ValueData -gt "30") {
							Write-Host -ForegroundColor Red "[-] The password age days is longer then 30"
						}
						
						# Check PwdExpirationProtectionEnabled
						if (($data2 | Where-Object -Property ValueName -Match PwdExpirationProtectionEnabled | Select-Object ValueData).ValueData -eq "1"){
							Write-Host -ForegroundColor DarkGreen "[+] The PwdExpirationProtectionEnabled is enabled"
						}
						Else {
							Write-Host -ForegroundColor Red "[-] The PwdExpirationProtectionEnabled is disabled or not configured (which means disabled)"
						}
						
						# Check AdmPwdEnabled
						if (($data2 | Where-Object -Property ValueName -Match AdmPwdEnabled | Select-Object ValueData).ValueData -eq "1"){
							Write-Host -ForegroundColor DarkGreen "[+] The LAPS policy is enabled"
						}
						Else {
							Write-Host -ForegroundColor Red "[-] The LAPS policy is disabled"
						}
					}
					else {
						Write-Host -ForegroundColor Red "[-] The policy could not be found!"
					}
			}
			Write-Host " "
		}
		else {
			Write-Host -ForegroundColor Red "[-] There is no GPO with LAPS in their name"
			Write-Host " "
		}
	
	# Check if there are systems where LAPS is enabled on
	Write-Host "---Checking if LAPS is enabled on any computerobject---"
	$data = Get-DomainComputer -Domain $Domain -Server $Server -Credential $Creds | Where-Object -Property ms-Mcs-AdmPwdExpirationTime | Select-Object samaccountname
	$file = "$data_path\laps_computers_enabled.txt"
	if ($data){ 
			$count = $data | Measure-Object | Select-Object -expand Count
			Write-Host -ForegroundColor DarkGreen "[+] There are $count systems where LAPS is enabled"
			Write-Host "[W] Writing to $file"
			$data | Out-File $file
			
			#Set lapsgpo to 1 to check if our user can access any LAPS passwords.
			$lapsgpo = 1
			Write-Host " "
			
			# Check if there are systems where LAPS isn't enabled on
			Write-Host "---Checking Windows computerobjects where LAPS isn't enabled---"
			$data = Get-DomainComputer -Domain $Domain -Server $Server -Credential $Creds | Where-Object {$_."ms-Mcs-AdmPwdExpirationTime" -Like $null -and $_.Operatingsystem -match "Windows" } | Select-Object samaccountname, lastlogon, whenchanged | Sort-Object whenchanged -Descending
			$file = "$data_path\laps_computers_disabled.txt"
			if ($data){ 
				$count = $data | Measure-Object | Select-Object -expand Count
				Write-Host -ForegroundColor Red "[-] There are $count Windows systems where LAPS isn't enabled"
				Write-Host "[W] Writing to $file"
				$data | Out-File $file
			}
			else {
				Write-Host -ForegroundColor DarkGreen "[+] There are no Windows systems where LAPS isn't enabled"
			}
			Write-Host " "
		}
		else {
			Write-Host -ForegroundColor Red "[-] There are no systems where LAPS is enabled"
			$file = "$findings_path\laps_notenabled.txt"
			Write-Host "[W] Writing to $file"
			echo "LAPS NOT ENABLED ON ANY COMPUTER" > $file
		}
	
	# If there is LAPS found in GPO or Computers with LAPS
	if ($lapsgpo -eq 1){ 
			# Check if current user can read LAPS passwords
			Write-Host "---Checking if current user can read LAPS passwords---"
			$data = Get-DomainComputer -Domain $Domain -Server $Server -Credential $Creds | Where-Object -Property ms-mcs-admpwd | Select-Object samaccountname, ms-mcs-admpwd
			if ($data){ 
					Write-Host -ForegroundColor Red "[-] The current user could read LAPS passwords"
					$file = "$findings_path\laps_passwords.txt"
					Write-Host "[W] Writing to $file"
					$data | Out-File $file
				}
				else {
					Write-Host -ForegroundColor DarkGreen "[-] The current user couldn't read any LAPS passwords!"
				}
		}
	Write-Host " "
}

Function Invoke-ADCheckDescription {
<#
.SYNOPSIS
Author: Jony Schats - 0xjs
Required Dependencies: None
Optional Dependencies: None

.DESCRIPTION
Requests all users, computers and groups with a description and exports there to a txt file.

.PARAMETER Domain
Specifies the domain to use for the query and creating outputdirectory.

.PARAMETER Server
Specifies an Active Directory server IP to bind to, e.g. 10.0.0.1

.PARAMETER User
Specifies the username to use for the query.

.PARAMETER Password
Specifies the Password in combination with the username to use for the query.

.PARAMETER OutputDirectory
Specifies the path to use for the output directory, defaults to the current directory.

.EXAMPLE
Invoke-ADCheckDescriptions -Domain 'contoso.com' -Server 'dc1.contoso.com' -User '0xjs' -Password 'Password01!'
#>

	#Parameters
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory=$true,HelpMessage="Enter a domain name here, e.g. contoso.com")]
		[ValidateNotNullOrEmpty()]
		[string]$Domain,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter a IP of a domain controller here, e.g. 10.0.0.1")]
		[ValidateNotNullOrEmpty()]
		[string]$Server,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter the username to connect with")]
		[ValidateNotNullOrEmpty()]
		[string]$User,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter the password of the user")]
		[ValidateNotNullOrEmpty()]
		[string]$Password,
		
		[Parameter(Mandatory=$false)]
		[ValidateNotNullOrEmpty()]
		[string]$OutputDirectory
	)
	
	if ($OutputDirectoryCreated -ne $true) {
		if ($PSBoundParameters['OutputDirectory']) {
			New-OutputDirectory -Domain $Domain -OutputDirectory $OutputDirectory
			}
			else {
				New-OutputDirectory -Domain $Domain
		}
	}
	
	if ($User -ne $Creds.Username) {
		Create-CredentialObject -User $User -Password $Password
	}	
	
	# Usernames with description, possible passwords
	Write-Host "---Checking description field for passwords---"
	$data = Get-DomainUser -Domain $Domain -Server $Server -Credential $Creds | Where-Object description | Select-Object samaccountname, description | Sort-Object description -Descending
	$file = "$checks_path\description_users.txt"
	if ($data){ 
			$count = $data | Measure-Object | Select-Object -expand Count
			Write-Host -ForegroundColor Yellow "[-] There are $count users that have a description, please manually check for passwords!"
			Write-Host "[W] Writing to $file"
			$data | Out-File $file
			
			$data2 = $data | Where-Object {$_.description -Match "pw" -or $_.description -match "pass" -or $_.description -match "ww" -or $_.description -match "wachtwoord"}
			if ($data2) {
				Write-Host " "
				$file = "$checks_path\description_users_passstrings.txt"
				$count = $data2 | Measure-Object | Select-Object -expand Count
				Write-Host -ForegroundColor Yellow "[-] There are $count users that have a description with the string pw, pass, ww or wachtwoord, please manually check for passwords!"
				Write-Host "[W] Writing to $file"
				$data2 | Out-File $file
			}
		}
		else {
			Write-Host -ForegroundColor DarkGreen "[+] There where no users with a description"
		}
	Write-Host " "
		
	# Groups with description, possible interesting information
	Write-Host "---Checking groups description field for interesting information---"
	$data = Get-DomainGroup -Domain $Domain -Server $Server -Credential $Creds | Where-Object description | Select-Object samaccountname, description | Sort-Object description -Descending
	$file = "$checks_path\description_groups.txt"
	if ($data){ 
			$count = $data | Measure-Object | Select-Object -expand Count
			Write-Host -ForegroundColor Yellow "[-] There are $count groups that have a description, please manually check for passwords or interesting information!"
			Write-Host "[W] Writing to $file"
			$data | Out-File $file
		}
		else {
			Write-Host -ForegroundColor DarkGreen "[+] There are no groups with a description"
		}
	Write-Host " "
	
	# Computers with description, possible interesting information
	Write-Host "---Checking computerobjects description field for interesting information---"
	$data = Get-DomainComputer -Domain $Domain -Server $Server -Credential $Creds | Where-Object description | Select-Object samaccountname, description | Sort-Object description -Descending
	$file = "$checks_path\description_computers.txt"
	if ($data){ 
			$count = $data | Measure-Object | Select-Object -expand Count
			Write-Host -ForegroundColor Yellow "[-] There are $count computerobjects that have a description, please manually check for passwords or interesting information!"
			Write-Host "[W] Writing to $file"
			$data | Out-File $file
		}
		else {
			Write-Host -ForegroundColor DarkGreen "[+] There are no computerobjects with a description"
		}
	Write-Host " "
}

Function Invoke-ADCheckRoasting {
<#
.SYNOPSIS
Author: Jony Schats - 0xjs
Required Dependencies: None
Optional Dependencies: None

.DESCRIPTION
Check is there are any kerberoastable domain admins, then checks for all users and kerberoasts every user. Then it checks for AS-REP roasting.

.PARAMETER Domain
Specifies the domain to use for the query and creating outputdirectory.

.PARAMETER Server
Specifies an Active Directory server IP to bind to, e.g. 10.0.0.1

.PARAMETER User
Specifies the username to use for the query.

.PARAMETER Password
Specifies the Password in combination with the username to use for the query.

.PARAMETER OutputDirectory
Specifies the path to use for the output directory, defaults to the current directory.

.PARAMETER SkipRoasting
If specified skips the kerberoasting and AS-REP roasting with Impacket.

.EXAMPLE
Invoke-ADCheckRoasting -Domain 'contoso.com' -Server 'dc1.contoso.com' -User '0xjs' -Password 'Password01!'
Does all the checks for Roasting.

.EXAMPLE
Invoke-ADCheckRoasting -Domain 'contoso.com' -Server 'dc1.contoso.com' -User '0xjs' -Password 'Password01!' -SkipRoasting
Does only enumeration and skips the execution of impacket
#>

	#Parameters
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory=$true,HelpMessage="Enter a domain name here, e.g. contoso.com")]
		[ValidateNotNullOrEmpty()]
		[string]$Domain,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter a IP of a domain controller here, e.g. 10.0.0.1")]
		[ValidateNotNullOrEmpty()]
		[string]$Server,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter the username to connect with")]
		[ValidateNotNullOrEmpty()]
		[string]$User,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter the password of the user")]
		[ValidateNotNullOrEmpty()]
		[string]$Password,
		
		[Parameter(Mandatory=$false)]
		[ValidateNotNullOrEmpty()]
		[string]$OutputDirectory,
		
		[Parameter(Mandatory = $false)]
		[Switch]
		$SkipRoasting
	)
	
	if ($OutputDirectoryCreated -ne $true) {
		if ($PSBoundParameters['OutputDirectory']) {
			New-OutputDirectory -Domain $Domain -OutputDirectory $OutputDirectory
			}
			else {
				New-OutputDirectory -Domain $Domain
		}
	}
	
	if ($User -ne $Creds.Username) {
		Create-CredentialObject -User $User -Password $Password
	}	
	
	# Check if Administrator accounts has SPN set (kerberoasting)
	Write-Host "---Checking kerberoastable administrators---"
	$file = "$findings_path\administrators_serviceprincipalname.txt"
	$data = Get-DomainGroupMember -Domain $Domain -Server $Server -Credential $Creds "Domain Admins" -Recurse | Get-DomainUser -Domain $Domain -Server $Server -Credential $Creds -SPN | Select-Object samaccountname, serviceprincipalname | Format-Table -Autosize 
	$data += Get-DomainGroupMember -Domain $Domain -Server $Server -Credential $Creds "Enterprise Admins" -Recurse | Get-DomainUser -Domain $Domain -Server $Server -Credential $Creds -SPN | Select-Object samaccountname, serviceprincipalname | Format-Table -Autosize 
	$data += Get-DomainGroupMember -Domain $Domain -Server $Server -Credential $Creds "Administrators" -Recurse | Get-DomainUser -Domain $Domain -Server $Server -Credential $Creds -SPN | Select-Object samaccountname, serviceprincipalname | Format-Table -Autosize 
	
	if ($data){ 
			$data | Out-File $file
			$data = Get-Content $file
			$data = $data | Sort-Object -Unique 
			$data = $data -replace 'samaccountname', '' -replace '--------------------', '' -replace '--------------', '' -replace 'serviceprincipalname', '' #remove strings
			$data = $data.Trim() | ? {$_.trim() -ne "" } #Remove spaces and white lines
			$count = $data | Measure-Object | Select-Object -expand Count
			Write-Host -ForegroundColor Red "[-] There are $count kerberoastable administrators"
			Write-Host "[W] Writing to $file"
			$data | Out-File $file
		}
		else {
			Write-Host -ForegroundColor DarkGreen "[+] There are no kerberoastable administrators"
		}
	Write-Host " "
	
	# Check users with SPN set (kerberoasting)
	Write-Host "---Checking kerberoastable users---"
	$data = Get-DomainUser -Domain $Domain -Server $Server -Credential $Creds -SPN | Where-Object -Property samaccountname -NotMatch krbtgt | Select-Object samaccountname, serviceprincipalname | Sort-Object -Property samaccountname
	$file = "$findings_path\users_serviceprincipalname.txt"
	$file_hashes = "$findings_path\users_kerberoast_hashes.txt"
	if ($data){ 
			$count = $data | Measure-Object | Select-Object -expand Count
			Write-Host -ForegroundColor Red "[-] There are $count kerberoastable users"
			Write-Host "[W] Writing to $file"
			$data | Out-File $file
			
			
			if (-Not $PSBoundParameters['SkipRoasting']) {
				# Run impacket and kerberoast
				$impacket_creds = $Domain + '/' + $User + ':' + $Password
				python $impacket_path\examples\GetUserSPNs.py -request -dc-ip $Server $impacket_creds -save -outputfile $file_hashes | Out-Null
				$hashes_count = cat $file_hashes -ErrorAction SilentlyContinue | Measure-Object | Select-Object -expand Count
				Write-Host -ForegroundColor Yellow "[+] Requested $hashes_count hashes, please crack with hashcat"
				Write-Host "[W] Writing to $file_hashes"
			}
		}
		else {
			Write-Host -ForegroundColor DarkGreen "[+] There are no kerberoastable users"
		}
	Write-Host " "
	
	# Check DONT_REQ_PREAUTH users
	Write-Host "---Checking if there are users with the DONT_REQ_PREAUTH attribute---"	
	$data = Get-DomainUser -Domain $Domain -Server $Server -Credential $Creds | Where-Object -Property useraccountcontrol -Match "DONT_REQ_PREAUTH" | Select-Object samaccountname | Sort-Object -Property samaccountname
	$file = "$findings_path\users_dontrequirepreath.txt"
	$file_hashes = "$findings_path\users_aspreproast_hashes.txt"
	if ($data){ 
			$count = $data | Measure-Object | Select-Object -expand Count
			Write-Host -ForegroundColor Red "[-] There are $count users with the attribute DONT_REQ_PREAUTH"
			Write-Host "[W] Writing to $file"
			$data | Out-File $file
			
			if (-Not $PSBoundParameters['SkipRoasting']) {
				# Run impacket and AS-REP Roast
				$impacket_creds = $Domain + '/' + $User + ':' + $Password
				python $impacket_path\examples\GetNPUsers.py -request -dc-ip $Server $impacket_creds -outputfile $file_hashes | Out-Null
				$hashes_count = cat $file_hashes -ErrorAction silentlycontinue | Measure-Object | Select-Object -expand Count
				Write-Host -ForegroundColor Yellow "[+] Requested $hashes_count hashes, please crack with hashcat"
				Write-Host "[W] Writing to $file_hashes"
			}
		}
		else {
			Write-Host -ForegroundColor DarkGreen "[+] There are no users with the attribute DONT_REQ_PREAUTH"
		}
	Write-Host " "
	
}

Function Invoke-ADCheckDelegation {
<#
.SYNOPSIS
Author: Jony Schats - 0xjs
Required Dependencies: None
Optional Dependencies: None

.DESCRIPTION
Checks users and computers for all types of delegation.

.PARAMETER Domain
Specifies the domain to use for the query and creating outputdirectory.

.PARAMETER Server
Specifies an Active Directory server IP to bind to, e.g. 10.0.0.1

.PARAMETER User
Specifies the username to use for the query.

.PARAMETER Password
Specifies the Password in combination with the username to use for the query.

.PARAMETER OutputDirectory
Specifies the path to use for the output directory, defaults to the current directory.

.EXAMPLE
Invoke-ADCheckDelegation -Domain 'contoso.com' -Server 'dc1.contoso.com' -User '0xjs' -Password 'Password01!'
#>

	#Parameters
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory=$true,HelpMessage="Enter a domain name here, e.g. contoso.com")]
		[ValidateNotNullOrEmpty()]
		[string]$Domain,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter a IP of a domain controller here, e.g. 10.0.0.1")]
		[ValidateNotNullOrEmpty()]
		[string]$Server,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter the username to connect with")]
		[ValidateNotNullOrEmpty()]
		[string]$User,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter the password of the user")]
		[ValidateNotNullOrEmpty()]
		[string]$Password,
		
		[Parameter(Mandatory=$false)]
		[ValidateNotNullOrEmpty()]
		[string]$OutputDirectory
	)
	
	if ($OutputDirectoryCreated -ne $true) {
		if ($PSBoundParameters['OutputDirectory']) {
			New-OutputDirectory -Domain $Domain -OutputDirectory $OutputDirectory
			}
			else {
				New-OutputDirectory -Domain $Domain
		}
	}
	
	if ($User -ne $Creds.Username) {
		Create-CredentialObject -User $User -Password $Password
	}	

	# Check for constrained delegation users
	Write-Host "---Checking constrained delegation users---"
	$data = Get-DomainUser -TrustedToAuth -Domain $Domain -Server $Server -Credential $Creds | Select-Object samaccountname, msds-allowedtodelegateto | Sort-Object -Property samaccountname
	$file = "$findings_path\users_constrained_delegation.txt"
	if ($data){ 
			$count = $data | Measure-Object | Select-Object -expand Count
			Write-Host -ForegroundColor Red "[-] There are $count users that have constrained delegation enabled"
			Write-Host "[W] Writing to $file"
			$data | Out-File $file
		}
		else {
			Write-Host -ForegroundColor DarkGreen "[+] There are no users with constrained delegation"
		}
	Write-Host " "
	
	# Check for unconstrained delegation user
	Write-Host "---Checking unconstrained delegation computerobjects, excluding domain-controllers---"	
	$data = Get-DomainUser -Domain $Domain -Server $Server -Credential $Creds | Where-Object -Property useraccountcontrol -Match TRUSTED_FOR_DELEGATION | Select-Object samaccountname | Sort-Object -Property samaccountname
	$file = "$findings_path\users_unconstrained_delegation.txt"
	if ($data){ 
			$count = $data | Measure-Object | Select-Object -expand Count
			Write-Host -ForegroundColor Red "[-] There are $count users that have unconstrained delegation enabled"
			Write-Host "[W] Writing to $file"
			$data | Out-File $file
		}
		else {
			Write-Host -ForegroundColor DarkGreen "[+] There are no users with unconstrained delegation"
		}
	Write-Host " "
	
	# Check for constrained delegation computerobjects
	Write-Host "---Checking constrained delegation computerobjects---"	
	$data = Get-DomainComputer -TrustedToAuth -Domain $Domain -Server $Server -Credential $Creds | Select-Object samaccountname, msds-allowedtodelegateto | Sort-Object -Property samaccountname
	$file = "$findings_path\computers_constrained_delegation.txt"
	if ($data){ 
			$count = $data | Measure-Object | Select-Object -expand Count
			Write-Host -ForegroundColor Red "[-] There are $count computerobjects that have constrained delegation enabled"
			Write-Host "[W] Writing to $file"
			$data | Out-File $file
		}
		else {
			Write-Host -ForegroundColor DarkGreen "[+] There are no computerobjects with constrained delegation"
		}
	Write-Host " "
	
	# Check for unconstrained delegation computeraccount
	Write-Host "---Checking unconstrained delegation computerobjects, excluding domain-controllers---"	
	$data = Get-DomainComputer -Unconstrained -Domain $Domain -Server $Server -Credential $Creds | Where-Object -Property useraccountcontrol -NotMatch "SERVER_TRUST_ACCOUNT" | Select-Object samaccountname | Sort-Object -Property samaccountname
	$file = "$findings_path\computers_unconstrained_delegation.txt"
	if ($data){ 
			$count = $data | Measure-Object | Select-Object -expand Count
			Write-Host -ForegroundColor Red "[-] There are $count computerobjects that have unconstrained delegation enabled"
			Write-Host "[W] Writing to $file"
			$data | Out-File $file
		}
		else {
			Write-Host -ForegroundColor DarkGreen "[+] There are no computerobjects with unconstrained delegation"
		}
	Write-Host " "
	
	# Check resouce based constrained delegation computerobjects
	Write-Host "---Checking resource based constrained delegation computerobjects---"	
	$data = Get-DomainComputer -Domain $Domain -Server $Server -Credential $Creds | Where-Object -Property msds-allowedtoactonbehalfofotheridentity | Select-Object -Property name, msds-allowedtoactonbehalfofotheridentity
	$file = "$findings_path\computers_resource_based_constrained_delegation.txt"
	if ($data){ 
		$count = $data | Measure-Object | Select-Object -expand Count
		Write-Host -ForegroundColor Red "[-] There are $count computerobjects that have resource based constrained delegation enabled"
		Write-Host -ForegroundColor Red "[-] Sign of compromise?"
		Write-Host "[W] Writing to $file"
		$data | Out-File $file
	}
	else {
		Write-Host -ForegroundColor DarkGreen "[+] There are no computerobjects with resource based constrained delegation"
	}
	Write-Host " "
}

Function Invoke-ADCheckUserAttributes {
<#
.SYNOPSIS
Author: Jony Schats - 0xjs
Required Dependencies: None
Optional Dependencies: None

.DESCRIPTION
Checks for user attributes which might decrease the security of a user their account.

.PARAMETER Domain
Specifies the domain to use for the query and creating outputdirectory.

.PARAMETER Server
Specifies an Active Directory server IP to bind to, e.g. 10.0.0.1

.PARAMETER User
Specifies the username to use for the query.

.PARAMETER Password
Specifies the Password in combination with the username to use for the query.

.PARAMETER OutputDirectory
Specifies the path to use for the output directory, defaults to the current directory.

.PARAMETER SkipEmptyPasswordGuess
If specified skips authenticating with a empty password for the users with PASSWD_NOTREQD attribute.

.EXAMPLE
Invoke-ADCheckUserAttributes -Domain 'contoso.com' -Server 'dc1.contoso.com' -User '0xjs' -Password 'Password01!'
#>

	#Parameters
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory=$true,HelpMessage="Enter a domain name here, e.g. contoso.com")]
		[ValidateNotNullOrEmpty()]
		[string]$Domain,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter a IP of a domain controller here, e.g. 10.0.0.1")]
		[ValidateNotNullOrEmpty()]
		[string]$Server,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter the username to connect with")]
		[ValidateNotNullOrEmpty()]
		[string]$User,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter the password of the user")]
		[ValidateNotNullOrEmpty()]
		[string]$Password,
		
		[Parameter(Mandatory=$false)]
		[ValidateNotNullOrEmpty()]
		[string]$OutputDirectory,		
				
		[Parameter(Mandatory = $false)]
		[Switch]
		$SkipEmptyPasswordGuess
	)
	
	if ($OutputDirectoryCreated -ne $true) {
		if ($PSBoundParameters['OutputDirectory']) {
			New-OutputDirectory -Domain $Domain -OutputDirectory $OutputDirectory
			}
			else {
				New-OutputDirectory -Domain $Domain
		}
	}
	
	if ($User -ne $Creds.Username) {
		Create-CredentialObject -User $User -Password $Password
	}	
	
	$data = Get-DomainUser -Domain $Domain -Server $Server -Credential $Creds
	
	# Check PASSWD_NOTREQD users
	Write-Host "---Checking if there are users with the PASSWD_NOTREQD attribute---"	
	$data2 = $data | Where-Object {$_.useraccountcontrol -Match "PASSWD_NOTREQD" -and $_.useraccountcontrol -notmatch "ACCOUNTDISABLE"} | Select-Object samaccountname | Sort-Object -Property samaccountname
	$file = "$findings_path\users_passwdnotreqd.txt"
	if ($data2){ 
			$count = $data2 | Measure-Object | Select-Object -expand Count
			Write-Host -ForegroundColor Red "[-] There are $count users with the attribute PASSWD_NOTREQD"
			Write-Host "[W] Writing to $file"
			$data2 | Out-File $file	
			Write-Host " "
			
			if (-Not $PSBoundParameters['SkipEmptyPasswordGuess']) {
				Write-Host "---Checking for users with empty password---"
				ForEach ($user in $data2.samaccountname){
					$samaccountname = $user
					$Credentials = New-Object System.Management.Automation.PSCredential("$samaccountname",(New-Object System.Security.SecureString))
					$data3 = Get-Domain -Domain $Domain -Credential $Credentials
					if ($data3){ 
						Write-Host -ForegroundColor Red "[-] The password for user $samaccountname is empty"
					}
					else {
						Write-Host -ForegroundColor DarkGreen "[+] The password for user $samaccountname isn't empty"
					}
				}
			}
		}
	else {
		Write-Host -ForegroundColor DarkGreen "[+] There are no users with the attribute PASSWD_NOTREQD"
	}
	Write-Host " "
		
	# Check DONT_EXPIRE_PASSWORD users
	Write-Host "---Checking if there are users with the DONT_EXPIRE_PASSWORD attribute---"	
	$data2 = $data | Where-Object -Property useraccountcontrol -Match "DONT_EXPIRE_PASSWORD" | Select-Object samaccountname | Sort-Object -Property samaccountname
	$file = "$findings_path\users_dontexpirepassword.txt"
	if ($data2){ 
			$count = $data2 | Measure-Object | Select-Object -expand Count
			Write-Host -ForegroundColor Red "[-] There are $count users with the attribute DONT_EXPIRE_PASSWORD"
			Write-Host "[W] Writing to $file"
			$data2 | Out-File $file
		}
		else {
			Write-Host -ForegroundColor DarkGreen "[+] There are no users with the attribute DONT_EXPIRE_PASSWORD"
		}
	Write-Host " "
	
	# Check if there are users with reversible encryption
	Write-Host "---Checking if there are users with the reversible encryption---"	
	$data2 = $data | Where-Object -Property useraccountcontrol -Match "ENCRYPTED_TEXT_PWD_ALLOWED" | Select-Object samaccountname | Sort-Object -Property samaccountname
	$file = "$findings_path\users_reversibleencryption.txt"
	if ($data2){ 
			$count = $data2 | Measure-Object | Select-Object -expand Count
			Write-Host -ForegroundColor Red "[-] There are $count users with reversible encryption"
			Write-Host "[W] Writing to $file"
			$data2 | Out-File $file
		}
		else {
			Write-Host -ForegroundColor DarkGreen "[+] There are no users with reversible encryption"
		}
	Write-Host " "
	
	# Check if there are users with DES encryption
	Write-Host "---Checking if there are users with DES encryption---"	
	$data2 = $data | Where-Object -Property useraccountcontrol -Match "USE_DES_KEY_ONLY" | Select-Object samaccountname | Sort-Object -Property samaccountname
	$file = "$findings_path\users_desencryption.txt"
	if ($data2){ 
			$count = $data2 | Measure-Object | Select-Object -expand Count
			Write-Host -ForegroundColor Red "[-] There are $count users with DES encryption"
			Write-Host "Writing to $file"
			$data2 | Out-File $file
		}
		else {
			Write-Host -ForegroundColor DarkGreen "[+] There are no users with DES encryption"
		}
	Write-Host " "
	
	# Check for Domain admins with old password
	Write-Host "---Checking if administrator accounts - that aren't disabled - have a password older then 365 days---"
	$file = "$findings_path\oldpassword_administrators.txt"
	$data = Get-DomainGroupMember -Domain $Domain -Server $Server -Credential $Creds "Domain Admins" -Recurse | Get-DomainUser -Domain $Domain -Server $Server -Credential $Creds | Where-Object {$_.pwdlastset -lt (Get-Date).AddDays(-365) -and $_.useraccountcontrol -notmatch "ACCOUNTDISABLE"} | Select-Object samaccountname, pwdlastset | Format-Table -Autosize | Out-File $file
	$data += Get-DomainGroupMember -Domain $Domain -Server $Server -Credential $Creds "Enterprise Admins" -Recurse | Get-DomainUser -Domain $Domain -Server $Server -Credential $Creds | Where-Object {$_.pwdlastset -lt (Get-Date).AddDays(-365) -and $_.useraccountcontrol -notmatch "ACCOUNTDISABLE"} | Select-Object samaccountname, pwdlastset | Format-Table -Autosize | Out-File -Append $file
	$data += Get-DomainGroupMember -Domain $Domain -Server $Server -Credential $Creds "Administrators" -Recurse | Get-DomainUser -Domain $Domain -Server $Server -Credential $Creds | Where-Object {$_.pwdlastset -lt (Get-Date).AddDays(-365) -and $_.useraccountcontrol -notmatch "ACCOUNTDISABLE"} | Select-Object samaccountname, pwdlastset | Format-Table -Autosize | Out-File -Append $file
	
	if ($data){ 
			$data | Out-File $file
			$data = Get-Content $file
			$data = $data | Sort-Object -Unique 
			$data = $data -replace 'samaccountname', '' -replace '--------------', '' #remove strings
			$data = $data.Trim() | ? {$_.trim() -ne "" } #Remove spaces and white lines
			$count = $data | Measure-Object | Select-Object -expand Count
			Write-Host -ForegroundColor Red "[-] There are $count enabled administrators with a password older then 365 days!"
			Write-Host "[W] Writing to $file"
			$data | Out-File $file
		}
		else {
			Write-Host -ForegroundColor DarkGreen "[+] There where no enabled administrators with a password older then 365 days"
		}
	Write-Host " "
	
	# Check for KRBTGT with old password
	Write-Host "---Checking if KRBTGT account has a password older then 365 days---"
	$data = Get-DomainUser -Domain $Domain -Server $Server -Credential $Creds krbtgt | Where-Object {$_.pwdlastset -lt (Get-Date).AddDays(-365)} | Select-Object samaccountname, pwdlastset 
	$file = "$findings_path\olpassword_krbtgt.txt"
	if ($data){ 
			Write-Host -ForegroundColor Red "[-] The password from the krbtgt is older then 365 days"
			Write-Host "[W] Writing to $file"
			$data | Out-File $file
		}
		else {
			Write-Host -ForegroundColor DarkGreen "[+] The password from the krbtgt is not older then 365 days"
		}
	Write-Host " "

}

Function Invoke-ADCheckOutdatedComputers {
<#
.SYNOPSIS
Author: Jony Schats - 0xjs
Required Dependencies: None
Optional Dependencies: None

.DESCRIPTION
Checks for computerobjects which are registered with an old operating system or a windows 10 version which is EOL.

.PARAMETER Domain
Specifies the domain to use for the query and creating outputdirectory.

.PARAMETER Server
Specifies an Active Directory server IP to bind to, e.g. 10.0.0.1

.PARAMETER User
Specifies the username to use for the query.

.PARAMETER Password
Specifies the Password in combination with the username to use for the query.

.PARAMETER OutputDirectory
Specifies the path to use for the output directory, defaults to the current directory.

.EXAMPLE
Invoke-ADCheckOutdatedComputers -Domain 'contoso.com' -Server 'dc1.contoso.com' -User '0xjs' -Password 'Password01!'
#>

	#Parameters
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory=$true,HelpMessage="Enter a domain name here, e.g. contoso.com")]
		[ValidateNotNullOrEmpty()]
		[string]$Domain,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter a IP of a domain controller here, e.g. 10.0.0.1")]
		[ValidateNotNullOrEmpty()]
		[string]$Server,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter the username to connect with")]
		[ValidateNotNullOrEmpty()]
		[string]$User,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter the password of the user")]
		[ValidateNotNullOrEmpty()]
		[string]$Password,
		
		[Parameter(Mandatory=$false)]
		[ValidateNotNullOrEmpty()]
		[string]$OutputDirectory
	)
	
	if ($OutputDirectoryCreated -ne $true) {
		if ($PSBoundParameters['OutputDirectory']) {
			New-OutputDirectory -Domain $Domain -OutputDirectory $OutputDirectory
			}
			else {
				New-OutputDirectory -Domain $Domain
		}
	}
	
	if ($User -ne $Creds.Username) {
		Create-CredentialObject -User $User -Password $Password
	}	
	
	# Checking for EOL operating systems in the AD
	Write-Host "---Checking if there are EOL operating systems in the AD---"
	$data = Get-DomainComputer  -Credential $Creds -Server $Server -Domain $Domain | Where-Object {$_.operatingsystem -match 'Windows 7' -or $_.operatingsystem -match 'Windows Server 2008' -or $_.operatingsystem -match 'Windows Server 2003' -or $_.operatingsystem -match 'XP'} | Select-Object samaccountname, operatingsystem, lastlogon | Sort-Object -Property lastlogon -Descending 
	$file = "$findings_path\computers_OS_EOL.txt"
	if ($data){ 
			$count = $data | Measure-Object | Select-Object -expand Count
			Write-Host -ForegroundColor Red "[-] There are $count computerobjects in the AD that are EOL"
			Write-Host "[W] Writing to $file"
			$data | Out-File $file
		}
		else {
			Write-Host -ForegroundColor DarkGreen "[+] There are no computerobjects in the AD that are EOL"
		}
	Write-Host " "
	
	# Checking for EOL operating systems in the AD
	Write-Host "---Checking if there are end of service Windows 10 operating systems in the AD---"
	$data = Get-DomainComputer  -Credential $Creds -Server $Server -Domain $Domain | Where-Object {$_.operatingsystem -match 'Windows 10'} | Where-Object {$_.operatingsystemversion -match 19041 -or $_.operatingsystemversion -match 18362 -or $_.operatingsystemversion -match 17134 -or $_.operatingsystemversion -match 16299 -or $_.operatingsystemversion -match 15063 -or $_.operatingsystemversion -match 10586 -or $_.operatingsystemversion -match 14393 -or $_.operatingsystemversion -match 10240} | Select-Object samaccountname, operatingsystem, operatingsystemversion, lastlogon | Sort-Object -Property lastlogon -Descending 
	$file = "$findings_path\computers_W10_EOS.txt"
	if ($data){ 
			$count = $data | Measure-Object | Select-Object -expand Count
			Write-Host -ForegroundColor Red "[-] There are $count Windows 10 computerobjects in the AD that are End Of Service"
			Write-Host "[W] Writing to $file"
			$data | Out-File $file
			Write-Host "[+] Replacing Powerview versions with more readable versions"
			Write-Host "End of servic versions at https://docs.microsoft.com/en-us/windows/release-health/release-information"
			(Get-Content $file) | Foreach-Object {
			$_ 	-replace '19041', '2004' `
				-replace '18362', '1903' `
				-replace '17134', '1803' `
				-replace '16299', '1709' `
				-replace '15063', '1703' `
				-replace '10586', '1511' `
				-replace '14393', '1607' `
				-replace '10240', '1507' 
			} | Set-Content $file
		}
		else {
			Write-Host -ForegroundColor DarkGreen "[+] There are no Windows 10 computerobjects computerobjects in the AD that are End Of Service"
		}
	Write-Host " "
}

Function Invoke-ADCheckInactiveObjects {
<#
.SYNOPSIS
Author: Jony Schats - 0xjs
Required Dependencies: None
Optional Dependencies: None

.DESCRIPTION
Checks for computerobjects which are registered with an old operating system or a windows 10 version which is EOL.

.PARAMETER Domain
Specifies the domain to use for the query and creating outputdirectory.

.PARAMETER Server
Specifies an Active Directory server IP to bind to, e.g. 10.0.0.1

.PARAMETER User
Specifies the username to use for the query.

.PARAMETER Password
Specifies the Password in combination with the username to use for the query.

.PARAMETER OutputDirectory
Specifies the path to use for the output directory, defaults to the current directory.

.EXAMPLE
Invoke-ADCheckInactiveObjects -Domain 'contoso.com' -Server 'dc1.contoso.com' -User '0xjs' -Password 'Password01!'
#>

	#Parameters
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory=$true,HelpMessage="Enter a domain name here, e.g. contoso.com")]
		[ValidateNotNullOrEmpty()]
		[string]$Domain,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter a IP of a domain controller here, e.g. 10.0.0.1")]
		[ValidateNotNullOrEmpty()]
		[string]$Server,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter the username to connect with")]
		[ValidateNotNullOrEmpty()]
		[string]$User,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter the password of the user")]
		[ValidateNotNullOrEmpty()]
		[string]$Password,
		
		[Parameter(Mandatory=$false)]
		[ValidateNotNullOrEmpty()]
		[string]$OutputDirectory
	)
	
	if ($OutputDirectoryCreated -ne $true) {
		if ($PSBoundParameters['OutputDirectory']) {
			New-OutputDirectory -Domain $Domain -OutputDirectory $OutputDirectory
			}
			else {
				New-OutputDirectory -Domain $Domain
		}
	}
	
	if ($User -ne $Creds.Username) {
		Create-CredentialObject -User $User -Password $Password
	}	
	
	# Checking for inactive computerobjects that have no login or login/pwdlastset older then 365 days
	#-or $_.lastlogon -Like $null
	Write-Host "---Checking if there are computerobjects that have no login or login/pwdlastset older then 365 days---"
	$data = Get-DomainComputer  -Credential $Creds -Server $Server -Domain $Domain | Where-Object {$_.lastlogon -lt (Get-Date).AddDays(-365) -and $_.pwdlastset -lt (Get-Date).AddDays(-365)} | select-object samaccountname, pwdlastset, lastlogon  | Sort-Object -Property lastlogon -Descending 
	$file = "$findings_path\computers_inactive.txt"
	if ($data){ 
			$count = $data | Measure-Object | Select-Object -expand Count
			Write-Host -ForegroundColor Red "[-] There are $count computerobjects in the AD that have no login or login & pwdlastset older then 365 days"
			Write-Host "Writing to $file"
			$data | Out-File $file
		}
		else {
			Write-Host -ForegroundColor DarkGreen "[+] There are no computerobjects in the AD that are inactive"
		}
	Write-Host " "
	
	# Checking for inactive users that didn't login for the last 365 days	
	Write-Host "---Checking if there are users that didn't login for 365 days---"
	#-and $_.lastlogon -notlike $null 
	$data = Get-DomainUser  -Credential $Creds -Server $Server -Domain $Domain | Where-Object {$_.lastlogon -lt (Get-Date).AddDays(-365) -and $_.useraccountcontrol -notmatch "ACCOUNTDISABLE" -and $_.pwdlastset -lt (Get-Date).AddDays(-365)}| select-object samaccountname, pwdlastset, lastlogon  | Sort-Object -Property lastlogon -Descending 
	$file = "$findings_path\users_inactive.txt"
	if ($data){ 
			$count = $data | Measure-Object | Select-Object -expand Count
			Write-Host -ForegroundColor Red "[-] There are $count users in the AD that have didn't login or changed their password in the last 365 days"
			Write-Host "[W] Writing to $file"
			$data | Out-File $file
		}
		else {
			Write-Host -ForegroundColor DarkGreen "[+] There are no users in the AD that are inactive (didn't login or changed their password in the last 365 days)"
		}
	Write-Host " "
}

Function Invoke-ADCheckPrivilegedObjects {
<#
.SYNOPSIS
Author: Jony Schats - 0xjs
Required Dependencies: None
Optional Dependencies: None

.DESCRIPTION
Multiple checks for privileged users and groups. Are all privileged users part of the protected users group or do they have the "This account is sensitive and cannot be delegated" flag. Are people member of the high privileged built in operator groups? And are computers member of the domain admin group?

.PARAMETER Domain
Specifies the domain to use for the query and creating outputdirectory.

.PARAMETER Server
Specifies an Active Directory server IP to bind to, e.g. 10.0.0.1

.PARAMETER User
Specifies the username to use for the query.

.PARAMETER Password
Specifies the Password in combination with the username to use for the query.

.PARAMETER OutputDirectory
Specifies the path to use for the output directory, defaults to the current directory.

.EXAMPLE
Invoke-ADCheckPrivilegedObjects -Domain 'contoso.com' -Server 'dc1.contoso.com' -User '0xjs' -Password 'Password01!'
#>

	#Parameters
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory=$true,HelpMessage="Enter a domain name here, e.g. contoso.com")]
		[ValidateNotNullOrEmpty()]
		[string]$Domain,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter a IP of a domain controller here, e.g. 10.0.0.1")]
		[ValidateNotNullOrEmpty()]
		[string]$Server,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter the username to connect with")]
		[ValidateNotNullOrEmpty()]
		[string]$User,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter the password of the user")]
		[ValidateNotNullOrEmpty()]
		[string]$Password,
		
		[Parameter(Mandatory=$false)]
		[ValidateNotNullOrEmpty()]
		[string]$OutputDirectory
	)

	if ($OutputDirectoryCreated -ne $true) {
		if ($PSBoundParameters['OutputDirectory']) {
			New-OutputDirectory -Domain $Domain -OutputDirectory $OutputDirectory
			}
			else {
				New-OutputDirectory -Domain $Domain
		}
	}
	
	if ($User -ne $Creds.Username) {
		Create-CredentialObject -User $User -Password $Password
	}	

	# Check if all privileged users are part of the protected users group
	Write-Host "---Checking if members of privileged groups are part of the protected users group---"
	$data = Get-DomainGroup -AdminCount -Domain $Domain -Server $Server -Credential $Creds | Get-DomainGroupMember -Domain $Domain -Server $Server -Credential $Creds -Recurse -ErrorAction silentlycontinue | Get-DomainUser -Domain $Domain -Server $Server -Credential $Creds | Where-Object {!($_.memberof -match "Protected Users")} | Select-Object samaccountname | Sort-object samaccountname -Unique
	$file = "$findings_path\administrators_notin_protectedusersgroup.txt"
	if ($data){ 
			$count = $data | Measure-Object | Select-Object -expand Count
			Write-Host -ForegroundColor Red "[-] There are $count privileged users not part of the protected users group"
			Write-Host "[W] Writing to $file"
			$data | Out-File $file
		}
		else {
			Write-Host -ForegroundColor DarkGreen "[+] There are no administrators that aren't in the protected users group"
		}
	Write-Host " "
	
	# Check if all privileged users have the flag "this account is sensitive and cannot be delegated"
	Write-Host "---Checking if members of privileged groups have the flag 'this account is sensitive and cannot be delegated'---"
	$data = Get-DomainGroup -AdminCount -Domain $Domain -Server $Server -Credential $Creds | Get-DomainGroupMember -Domain $Domain -Server $Server -Credential $Creds -Recurse -ErrorAction silentlycontinue | Get-DomainUser -Domain $Domain -Server $Server -Credential $Creds -Allowdelegation | Where-Object {!($_.memberof -match "Protected Users")} | Select-Object samaccountname | Sort-object samaccountname -Unique
	$file = "$findings_path\administrators_delegation_flag.txt"
	if ($data){ 
			$count = $data | Measure-Object | Select-Object -expand Count
			Write-Host -ForegroundColor Red "[-] There are $count privileged users without the flag 'this account is sensitive and cannot be delegated' that aren't in the Protected Users group"
			Write-Host "[W] Writing to $file"
			$data | Out-File $file
		}
		else {
			Write-Host -ForegroundColor DarkGreen "[+] There are no high privileged users without the flag 'this account is sensitive and cannot be delegated' that aren't in the Protected Users group"
		}
	Write-Host " "
	
	# Check if there are members part of some privileged groups
	Write-Host "---Checking if there are members in high privileged groups---"
	$data = Get-DomainGroup -Domain $Domain -Server $Server -Credential $Creds "Account Operators" | Get-DomainGroupMember -Domain $Domain -Server $Server -Credential $Creds -Recurse | Get-DomainUser -Domain $Domain -Server $Server -Credential $Creds | Where-Object {!($_.memberof -match "Domain Admins" -or $_.memberof -match "Enterprise Admins")} | Select-Object samaccountname
	$file = "$checks_path\users_highprivilegegroups.txt"
	if ($data){ 
			$count = $data | Measure-Object | Select-Object -expand Count
			Write-Host -ForegroundColor Red "[-] There are $count users in the Account Operators group that aren't Domain- or Enterprise Administrators"
			Write-Host "[W] Writing to $file"
			"Account Operators" | Out-File $file -Append
			$data | Out-File $file -Append
		}
		else {
			Write-Host -ForegroundColor DarkGreen "[+] There are no users in the Account Operators group"
		}
	
	$data = Get-DomainGroup -Domain $Domain -Server $Server -Credential $Creds "Backup Operators" | Get-DomainGroupMember -Domain $Domain -Server $Server -Credential $Creds -Recurse | Get-DomainUser -Domain $Domain -Server $Server -Credential $Creds | Where-Object {!($_.memberof -match "Domain Admins" -or $_.memberof -match "Enterprise Admins")} | Select-Object samaccountname
	if ($data){ 
			$count = $data | Measure-Object | Select-Object -expand Count
			Write-Host -ForegroundColor Red "[-] There are $count users in the Backup Operators group that aren't Domain- or Enterprise Administrators"
			Write-Host "[W] Writing to $file"
			"Backup Operators" | Out-File $file -Append
			$data | Out-File $file -Append
		}
		else {
			Write-Host -ForegroundColor DarkGreen "[+] There are no users in the Backup Operators group"
		}
	
	$data = Get-DomainGroup -Domain $Domain -Server $Server -Credential $Creds "Print Operators" | Get-DomainGroupMember -Domain $Domain -Server $Server -Credential $Creds -Recurse | Get-DomainUser -Domain $Domain -Server $Server -Credential $Creds | Where-Object {!($_.memberof -match "Domain Admins" -or $_.memberof -match "Enterprise Admins")} | Select-Object samaccountname
	if ($data){ 
			$count = $data | Measure-Object | Select-Object -expand Count
			Write-Host -ForegroundColor Red "[-] There are $count users in the Print Operators group that aren't Domain- or Enterprise Administrators"
			Write-Host "[W] Writing to $file"
			"Print Operators" | Out-File $file -Append
			$data | Out-File $file -Append
		}
		else {
			Write-Host -ForegroundColor DarkGreen "[+] There are no users in the Print Operators group"
		}
		
	$data = Get-DomainGroup -Domain $Domain -Server $Server -Credential $Creds "DNS Admins" | Get-DomainGroupMember -Domain $Domain -Server $Server -Credential $Creds -Recurse | Get-DomainUser -Domain $Domain -Server $Server -Credential $Creds | Where-Object {!($_.memberof -match "Domain Admins" -or $_.memberof -match "Enterprise Admins")} | Select-Object samaccountname
	if ($data){
			$count = $data | Measure-Object | Select-Object -expand Count
			Write-Host -ForegroundColor Red "[-] There are $count users in the DNS Admins group that aren't Domain- or Enterprise Administrators"
			Write-Host "[W] Writing to $file"
			"Print Operators" | Out-File $file -Append
			$data | Out-File $file -Append
		}
		else {
			Write-Host -ForegroundColor DarkGreen "[+] There are no users in the DNS Admins group"
		}
	
	$data = Get-DomainGroup -Domain $Domain -Server $Server -Credential $Creds "Schema Admins" | Get-DomainGroupMember -Domain $Domain -Server $Server -Credential $Creds -Recurse | Get-DomainUser -Domain $Domain -Server $Server -Credential $Creds | Where-Object {!($_.memberof -match "Domain Admins" -or $_.memberof -match "Enterprise Admins")} | Select-Object samaccountname
	if ($data){ 
			$count = $data | Measure-Object | Select-Object -expand Count
			Write-Host -ForegroundColor Red "[-] There are $count users in the Schema Admins group that aren't Domain- or Enterprise Administrators"
			Write-Host "[W] Writing to $file"
			"Backup Operators" | Out-File $file -Append
			$data | Out-File $file -Append
		}
		else {
			Write-Host -ForegroundColor DarkGreen "[+] There are no users in the Schema Admins group"
		}
	Write-Host " "
	
	# Check if there is a computer part of a high privileged group
	Write-Host "---Checking if there are computerobjects part ofhigh privileged groups---"
	$data = Get-DomainGroup -Domain $Domain -Server $Server -Credential $Creds -AdminCount | Get-DomainGroupMember -Domain $Domain -Server $Server -Credential $Creds -Recurse -ErrorAction Silentlycontinue -WarningAction Silentlycontinue | Where-Object -Property MemberObjectClass -Match computer | Select-Object MemberName
	$file = "$findings_path\computers_part_of_highprivilegedgroups.txt"
	if ($data){ 
			$count = $data | Measure-Object | Select-Object -expand Count
			Write-Host -ForegroundColor Red "[-] There are $count computerobjects part of a high privileged groups"
			Write-Host "[W] Writing to $file"
			$data | Out-File $file
		}
		else {
			Write-Host -ForegroundColor DarkGreen "[+] There are no computerobjects part of a high privileged groups"
		}
	Write-Host " "
}

Function Invoke-ADCheckDomainJoin {
<#
.SYNOPSIS
Author: Jony Schats - 0xjs
Required Dependencies: None
Optional Dependencies: None

.DESCRIPTION
Check who can join computers to the domain. By default the "Authenticated users group" is able to join computers to the domain.

.PARAMETER Domain
Specifies the domain to use for the query and creating outputdirectory.

.PARAMETER Server
Specifies an Active Directory server IP to bind to, e.g. 10.0.0.1

.PARAMETER User
Specifies the username to use for the query.

.PARAMETER Password
Specifies the Password in combination with the username to use for the query.

.PARAMETER OutputDirectory
Specifies the path to use for the output directory, defaults to the current directory.

.EXAMPLE
Invoke-ADCheckDomainJoin -Domain 'contoso.com' -Server 'dc1.contoso.com' -User '0xjs' -Password 'Password01!'
#>

	#Parameters
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory=$true,HelpMessage="Enter a domain name here, e.g. contoso.com")]
		[ValidateNotNullOrEmpty()]
		[string]$Domain,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter a IP of a domain controller here, e.g. 10.0.0.1")]
		[ValidateNotNullOrEmpty()]
		[string]$Server,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter the username to connect with")]
		[ValidateNotNullOrEmpty()]
		[string]$User,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter the password of the user")]
		[ValidateNotNullOrEmpty()]
		[string]$Password,
		
		[Parameter(Mandatory=$false)]
		[ValidateNotNullOrEmpty()]
		[string]$OutputDirectory
	)

	if ($OutputDirectoryCreated -ne $true) {
		if ($PSBoundParameters['OutputDirectory']) {
			New-OutputDirectory -Domain $Domain -OutputDirectory $OutputDirectory
			}
			else {
				New-OutputDirectory -Domain $Domain
		}
	}
	
	if ($User -ne $Creds.Username) {
		Create-CredentialObject -User $User -Password $Password
	}	

	# Check who can add computerobjects to the domain
	Write-Host "---Checking who can add computerobjects to the domain---"
	$data = (Get-DomainPolicy -Policy DC -Domain $Domain -Server $Server -Credential $Creds).PrivilegeRights.SeMachineAccountPrivilege.Trim("*") | Get-DomainObject -Domain $Domain -Server $Server -Credential $Creds | Select-Object name
	$file = "$findings_path\authenticated_users_can_join_domain.txt"
	if ($data.name -eq "S-1-5-11"){ 
			$DomainSid = Get-DomainSID -Domain $Domain -Server $Server -Credential $Creds
			$MachineAccountQouta = Get-DomainObject -Domain $Domain -Server $Server -Credential $Creds | Where-Object objectsid -Like $DomainSid | Select-Object ms-ds-machineaccountquota
			
			if ($MachineAccountQouta."ms-ds-machineaccountquota" -eq 0) {
				Write-Host -ForegroundColor DarkGreen "[+] The authenticated users group(S-1-5-11) can not add computerobjects to the domain"
			}
			elseif ($MachineAccountQouta."ms-ds-machineaccountquota" -ge 1) {
				$count = $MachineAccountQouta."ms-ds-machineaccountquota"
				Write-Host -ForegroundColor Red "[-] The authenticated users group(S-1-5-11) can add $count computerobjects to the domain"
				Write-Host "[W] Writing to $file"
				$data | Out-File $file
				$file = "$checks_path\can_join_domain_amount.txt"
				Write-Host "[W] Writing amount of computerobjects that can be joined to the domain by the object to $file"
				$data2 | Out-File $file
			}
			elseif ($MachineAccountQouta."ms-ds-machineaccountquota" -Match $null) {
				Write-Host -ForegroundColor Red "[-] The authenticated users group(S-1-5-11) can add unlimited computerobjects to the domain"
				Write-Host "[W] Writing to $file"
				$data | Out-File $file
				$file = "$checks_path\can_join_domain_amount.txt"
			}	
			else {
				$count = 0
				Write-Host -ForeGroundColor Yellow "[-] Failed to get ms-ds-machineaccountquota please manually check"
			}
	}
	else {
		$file = "$checks_path\can_join_domain.txt"
		Write-Host -ForegroundColor DarkGreen "[+] The authenticated users group can't add computerobjects to the domain"
		Write-Host -ForegroundColor Yellow "[-] Please manually check which users or groups can add computerobjects to the domain"
		Write-Host "[W] Writing to $file"
		$data | Out-File $file
		$data = Get-DomainObject -Credential $creds -Domain $Domain -Server $Server | Where-Object ms-ds-machineaccountquota | select-object ms-ds-machineaccountquota
		$count = $data2."ms-ds-machineaccountquota"
		$file = "$checks_path\can_join_domain_amount.txt"
		Write-Host "[W] Writing amount of computerobjects that can be joined to the domain by the object to $file"
		$data | Out-File $file
	}
	Write-Host " "
}

Function Invoke-ADCheckReachableComputers {
<#
.SYNOPSIS
Author: Jony Schats - 0xjs
Required Dependencies: None
Optional Dependencies: None

.DESCRIPTION
Check which computers are reachable from the current machine with Get-NetConnection (ping).

.PARAMETER Domain
Specifies the domain to use for the query and creating outputdirectory.

.PARAMETER Server
Specifies an Active Directory server IP to bind to, e.g. 10.0.0.1

.PARAMETER User
Specifies the username to use for the query.

.PARAMETER Password
Specifies the Password in combination with the username to use for the query.

.PARAMETER OutputDirectory
Specifies the path to use for the output directory, defaults to the current directory.

.EXAMPLE
Invoke-ADCheckReachableComputers -Domain 'contoso.com' -Server 'dc1.contoso.com' -User '0xjs' -Password 'Password01!'
#>

	#Parameters
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory=$true,HelpMessage="Enter a domain name here, e.g. contoso.com")]
		[ValidateNotNullOrEmpty()]
		[string]$Domain,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter a IP of a domain controller here, e.g. 10.0.0.1")]
		[ValidateNotNullOrEmpty()]
		[string]$Server,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter the username to connect with")]
		[ValidateNotNullOrEmpty()]
		[string]$User,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter the password of the user")]
		[ValidateNotNullOrEmpty()]
		[string]$Password,
		
		[Parameter(Mandatory=$false)]
		[ValidateNotNullOrEmpty()]
		[string]$OutputDirectory
	)

	if ($OutputDirectoryCreated -ne $true) {
		if ($PSBoundParameters['OutputDirectory']) {
			New-OutputDirectory -Domain $Domain -OutputDirectory $OutputDirectory
			}
			else {
				New-OutputDirectory -Domain $Domain
		}
	}
	
	if ($User -ne $Creds.Username) {
		Create-CredentialObject -User $User -Password $Password
	}	
	
	# Check if there are reachable computers
	Write-Host "---Checking which machines are reachable from current machine through ping---"
	$data = Get-DomainComputer -Domain $Domain -Server $Server -Credential $Creds -Ping -ErrorAction silentlycontinue | Where-Object dnshostname | Select-Object dnshostname | Sort-Object
	$file = "$data_path\computers_accessible.txt"
	if ($data){ 
			$count = $data | Measure-Object | Select-Object -expand Count
			Write-Host -ForegroundColor DarkGreen "[+] There are $count computers which are reachable"
			Write-Host "[W] Writing to $file"
			$data | Out-File -Encoding utf8 $file
			$data = Get-Content $file
			$data = $data | Sort-Object -Unique 
			$data = $data -replace 'dnshostname', '' -replace '-----------', '' #remove strings
			$data = $data.Trim() | ? {$_.trim() -ne "" } #Remove spaces and white lines
			$data = $data | Sort-Object -Unique
			echo " " | Out-File -Encoding utf8 $file
			$data | Out-File -Encoding utf8 $file -Append
		}
		else {
			Write-Host -ForegroundColor Red "[+] There are no reachable computers, probably something wrong with DNS"
		}
	Write-Host " "
}

Function Invoke-ADCheckSysvolPassword {
<#
.SYNOPSIS
Author: Jony Schats - 0xjs
Required Dependencies: None
Optional Dependencies: None

.DESCRIPTION
Mounts the sysvol and checks for the string password in all policies.

.PARAMETER Domain
Specifies the domain to use for the query and creating outputdirectory.

.PARAMETER Server
Specifies an Active Directory server IP to bind to, e.g. 10.0.0.1

.PARAMETER User
Specifies the username to use for the query.

.PARAMETER Password
Specifies the Password in combination with the username to use for the query.

.PARAMETER OutputDirectory
Specifies the path to use for the output directory, defaults to the current directory.

.EXAMPLE
Invoke-ADCheckSysvolPassword -Domain 'contoso.com' -Server 'dc1.contoso.com' -User '0xjs' -Password 'Password01!'
#>

	#Parameters
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory=$true,HelpMessage="Enter a domain name here, e.g. contoso.com")]
		[ValidateNotNullOrEmpty()]
		[string]$Domain,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter a IP of a domain controller here, e.g. 10.0.0.1")]
		[ValidateNotNullOrEmpty()]
		[string]$Server,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter the username to connect with")]
		[ValidateNotNullOrEmpty()]
		[string]$User,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter the password of the user")]
		[ValidateNotNullOrEmpty()]
		[string]$Password,
		
		[Parameter(Mandatory=$false)]
		[ValidateNotNullOrEmpty()]
		[string]$OutputDirectory
	)

	if ($OutputDirectoryCreated -ne $true) {
		if ($PSBoundParameters['OutputDirectory']) {
			New-OutputDirectory -Domain $Domain -OutputDirectory $OutputDirectory
			}
			else {
				New-OutputDirectory -Domain $Domain
		}
	}
	
	if ($User -ne $Creds.Username) {
		Create-CredentialObject -User $User -Password $Password
	}	

	# Look through sysvol on each domain controller for the string password in all *xml files
	Write-Host "---Checking if there are passwords in the SYSVOL share---"
	Write-Host "This might take a while"
	$file = "$checks_path\sysvol_passwords.txt"
	$data = Get-DomainController -Domain $Domain -Server $Server -Credential $Creds
	ForEach ($dc in $data){
		$name = $dc.name
		$hostname = $dc.dnshostname
		Write-Host "[+] Checking SYSVOL of $name"
		New-PSDrive -Name $dc.name -PSProvider FileSystem -Root \\$hostname\SYSVOL -Credential $Creds | out-null
		$data = Get-ChildItem -Recurse -Path \\$hostname\SYSVOL\$Domain\Policies\*.xml -ErrorAction silentlycontinue | Select-String -Pattern "password"
		if ($data){ 
			$count = $data | Measure-Object | Select-Object -expand Count
			Write-Host -ForegroundColor Yellow "[-] There might be $count passwords in the SYSVOL of $name. Please manually check"
			Write-Host "Writing to $file"
			$data | Add-Content $file
		}
		else {
			Write-Host -ForegroundColor DarkGreen "[+] There are no passwords in the sysvol of $name"
		}
	}
	Write-Host " "
}

Function Invoke-ADCheckNetlogonPassword {
<#
.SYNOPSIS
Author: Jony Schats - 0xjs
Required Dependencies: None
Optional Dependencies: None

.DESCRIPTION
Mounts the netlogon share and checks for the string password in all files.

.PARAMETER Domain
Specifies the domain to use for the query and creating outputdirectory.

.PARAMETER Server
Specifies an Active Directory server IP to bind to, e.g. 10.0.0.1

.PARAMETER User
Specifies the username to use for the query.

.PARAMETER Password
Specifies the Password in combination with the username to use for the query.

.PARAMETER OutputDirectory
Specifies the path to use for the output directory, defaults to the current directory.

.EXAMPLE
Invoke-ADCheckNetlogonPassword -Domain 'contoso.com' -Server 'dc1.contoso.com' -User '0xjs' -Password 'Password01!'
#>

	#Parameters
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory=$true,HelpMessage="Enter a domain name here, e.g. contoso.com")]
		[ValidateNotNullOrEmpty()]
		[string]$Domain,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter a IP of a domain controller here, e.g. 10.0.0.1")]
		[ValidateNotNullOrEmpty()]
		[string]$Server,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter the username to connect with")]
		[ValidateNotNullOrEmpty()]
		[string]$User,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter the password of the user")]
		[ValidateNotNullOrEmpty()]
		[string]$Password,
		
		[Parameter(Mandatory=$false)]
		[ValidateNotNullOrEmpty()]
		[string]$OutputDirectory
	)

	if ($OutputDirectoryCreated -ne $true) {
		if ($PSBoundParameters['OutputDirectory']) {
			New-OutputDirectory -Domain $Domain -OutputDirectory $OutputDirectory
			}
			else {
				New-OutputDirectory -Domain $Domain
		}
	}
	
	if ($User -ne $Creds.Username) {
		Create-CredentialObject -User $User -Password $Password
	}	

	# Look through Netlogon on each domain controller for the string password in all *xml files
	Write-Host "---Checking if there are passwords in the NETLOGON share---"
	Write-Host "This might take a while"
	$file = "$checks_path\netlogon_passwords.txt"
	$data = Get-DomainController -Domain $Domain -Server $Server -Credential $Creds
	ForEach ($dc in $data){
		$name = $dc.name
		$hostname = $dc.dnshostname
		Write-Host "[+] Checking NETLOGON of $name"
		$MountName = "$name" + "-netlogon"
		New-PSDrive -Name "$MountName" -PSProvider FileSystem -Root \\$hostname\NETLOGON -Credential $Creds | out-null
		$data = Get-ChildItem -Recurse -Path \\$hostname\NETLOGON\* -ErrorAction silentlycontinue | Select-String -Pattern "pass"
		if ($data){ 
			$count = $data | Measure-Object | Select-Object -expand Count
			Write-Host -ForegroundColor Yellow "[-] There might be $count passwords(string pass) in the NETLOGON of $name. Please manually check"
			Write-Host "Writing to $file"
			$data | Add-Content $file
		}
		else {
			Write-Host -ForegroundColor DarkGreen "[+] There are no passwords in the NETLOGON of $name"
		}
	}
	Write-Host " "
}

Function Invoke-ADCheckSMB {
<#
.SYNOPSIS
Author: Jony Schats - 0xjs
Required Dependencies: Invoke-ADCheckReachableComputers
Optional Dependencies: None

.DESCRIPTION
Run crackmapexec with the provided credentials against all reachable computers within the domain and enumerate shares. Save the output which is getting parsed to find hosts with SMBv1 enabled, Signing false and creatte a list of all readable and writeable shares.

.PARAMETER Domain
Specifies the domain to use for the query and creating outputdirectory.

.PARAMETER Server
Specifies an Active Directory server IP to bind to, e.g. 10.0.0.1

.PARAMETER User
Specifies the username to use for the query.

.PARAMETER Password
Specifies the Password in combination with the username to use for the query.

.PARAMETER OutputDirectory
Specifies the path to use for the output directory, defaults to the current directory.

.EXAMPLE
Invoke-ADCheckSMB -Domain 'contoso.com' -Server 'dc1.contoso.com' -User '0xjs' -Password 'Password01!'
#>

	#Parameters
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory=$true,HelpMessage="Enter a domain name here, e.g. contoso.com")]
		[ValidateNotNullOrEmpty()]
		[string]$Domain,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter a IP of a domain controller here, e.g. 10.0.0.1")]
		[ValidateNotNullOrEmpty()]
		[string]$Server,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter the username to connect with")]
		[ValidateNotNullOrEmpty()]
		[string]$User,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter the password of the user")]
		[ValidateNotNullOrEmpty()]
		[string]$Password,
		
		[Parameter(Mandatory=$false)]
		[ValidateNotNullOrEmpty()]
		[string]$OutputDirectory
	)

	if ($OutputDirectoryCreated -ne $true) {
		if ($PSBoundParameters['OutputDirectory']) {
			New-OutputDirectory -Domain $Domain -OutputDirectory $OutputDirectory
			}
			else {
				New-OutputDirectory -Domain $Domain
		}
	}
	
	if (-not(Test-Path -Path $data_path\computers_accessible.txt)) {
		Invoke-ADCheckReachableComputers -Domain $Domain -Server $Server -User $User -Password $Password
	}
	
	# Collecting SMB data and shares with crackmapexec
	Write-Host "---Running crackmapexec against each reachable host enumerating SMB data and shares---"
	Write-Host -ForeGroundColor yellow "[+] Crackmapexec will hang and needs a enter to continue"
	$data = python.exe $CME_Path smb $data_path\computers_accessible.txt -d $Domain -u $User -p $Password --shares 2> null
	$file = "$data_path\crackmapexec_reachablecomputers.txt"
	if ($data){ 
			Write-Host "[W] Writing to $file"
			# Remove the colors from the data
			$data = $data -replace '\x1b\[[0-9;]*m'
			$data | Out-File -Encoding utf8 $file
			Write-Host " "
			
			# Filtering crackmapexec data for SMBv1 and signing
			$data2 = $data | Select-String "name:"
			# Remove the (R) String
			$data2 = $data2 -replace '\(R\)', ''
			# Split the output to name:<COMPuTERNAME> (domain:<DOMAIN>) (signing:False) (SMBv1:False)
			$data2 = foreach ($line in $data2) {$line.split("(",2)[1]}
			# Removing strings so we can create a PS Object
			$data2 = $data2 -replace 'name:', '' -replace 'signing:', '' -replace 'SMBv1:', '' -replace '\(', '' -replace '\)', ''
			# Selecting the hostname, SMBv1 and Signing values
			$data2 = $data2 | ConvertFrom-String | Select-Object p1, p3, p4
			# Renaming the p11, p13 and p14
			$data2 = $data2 | Add-Member -MemberType AliasProperty -Name hostname -Value P1 -PassThru | Add-Member -MemberType AliasProperty -Name signing -Value P3 -PassThru | Add-Member -MemberType AliasProperty -Name smbv1 -Value P4 -PassThru | Select-Object hostname, signing, smbv1
			
			# Checking for SMBV1
			Write-Host "---Checking for hosts which have SMBV1 enabled---"
			$data3 = $data2 | Where-Object -Property smbv1 -EQ True | Select-Object hostname
			$file = "$findings_path\computers_smbv1.txt"
			if ($data3){ 
					$count = $data3 | Measure-Object | Select-Object -expand Count
					Write-Host -ForegroundColor Red "[+] There are $count reachable computers which have SMBV1 enabled (SMBv1:True)"
					Write-Host "[W] Writing to $file"
					$data3 | Out-File -Encoding utf8 $file
				}
				else {
					Write-Host -ForegroundColor DarkGreen "[+] There are no reachable computers which have SMBV1 enabled (SMBv1:True)"
				}
			Write-Host " "
			
			# Checking for SMB Signing
			Write-Host "---Checking for hosts without signing---"
			$data3 = $data2 | Where-Object -Property signing -EQ False | Select-Object hostname
			$file = "$findings_path\computers_nosigning.txt"
			if ($data3){ 
					$count = $data3 | Measure-Object | Select-Object -expand Count
					Write-Host -ForegroundColor Red "[+] There are $count reachable computers which doesn't require signing (Signing:False)"
					Write-Host "[W] Writing to $file"
					$data3 | Out-File -Encoding utf8 $file
				}
				else {
					Write-Host -ForegroundColor DarkGreen "[+] There are no reachable computers which do not require signing (Signing:False)"
				}
			Write-Host " "
			
			# Checking for readable shares
			Write-Host "---Checking for shares with READ access---"
			$file = "$data_path\shares_read_access.txt"
			$data2 = $data | Select-String "READ" | Select-String -NotMatch IPC | Select-String -NotMatch PRINT
			if ($data2){ 
					$count = $data2 | Measure-Object | Select-Object -expand Count
					Write-Host -ForegroundColor Yellow "[+] There are $count shares the current user can READ"
					Write-Host "[W] Writing to $file"
					$data2 | Out-File -Encoding utf8 $file
				}
				else {
					Write-Host -ForegroundColor DarkGreen "[+] There are no shares the current user can READ"
				}
			Write-Host " "
			
			# Checking for writeable shares
			Write-Host "---Checking for shares with WRITE access---"
			$data2 = $data | Select-String "WRITE" | Select-String -NotMatch IPC | Select-String -NotMatch PRINT
			$file = "$data_path\shares_write_access.txt"
			if ($data3){ 
					$count = $data2 | Measure-Object | Select-Object -expand Count
					Write-Host -ForegroundColor Yellow "[+] There are $count shares the current user can WRITE to"
					Write-Host "[W] Writing to $file"
					$data2 | Out-File -Encoding utf8 $file
				}
				else {
					Write-Host -ForegroundColor DarkGreen "[+] There are no shares the current user can WRITE to"
				}
			Write-Host " "
	}
}

Function Invoke-ADCheckPrintspoolerDC {
<#
.SYNOPSIS
Author: Jony Schats - 0xjs
Required Dependencies: None 
Optional Dependencies: None

.DESCRIPTION
Check if the printspooler service is running on each DC in the domain.

.PARAMETER Domain
Specifies the domain to use for the query and creating outputdirectory.

.PARAMETER Server
Specifies an Active Directory server IP to bind to, e.g. 10.0.0.1

.PARAMETER User
Specifies the username to use for the query.

.PARAMETER Password
Specifies the Password in combination with the username to use for the query.

.PARAMETER OutputDirectory
Specifies the path to use for the output directory, defaults to the current directory.

.EXAMPLE
Invoke-ADCheckPrintspoolerDC -Domain 'contoso.com' -Server 'dc1.contoso.com' -User '0xjs' -Password 'Password01!'
#>

	#Parameters
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory=$true,HelpMessage="Enter a domain name here, e.g. contoso.com")]
		[ValidateNotNullOrEmpty()]
		[string]$Domain,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter a IP of a domain controller here, e.g. 10.0.0.1")]
		[ValidateNotNullOrEmpty()]
		[string]$Server,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter the username to connect with")]
		[ValidateNotNullOrEmpty()]
		[string]$User,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter the password of the user")]
		[ValidateNotNullOrEmpty()]
		[string]$Password,
		
		[Parameter(Mandatory=$false)]
		[ValidateNotNullOrEmpty()]
		[string]$OutputDirectory
	)

	if ($User -ne $Creds.Username) {
		Create-CredentialObject -User $User -Password $Password
	}	

	if ($OutputDirectoryCreated -ne $true) {
		if ($PSBoundParameters['OutputDirectory']) {
			New-OutputDirectory -Domain $Domain -OutputDirectory $OutputDirectory
			}
			else {
				New-OutputDirectory -Domain $Domain
		}
	}
	
	Write-Host "---Checking printspooler service on each DC---"
	$file = "$findings_path\printspooler_domaincontrollers.txt"
	$data = Get-DomainController -Domain $Domain -Server $Server -Credential $Creds
	ForEach ($dc in $data){
		$name = $dc.name
		$hostname = $dc.dnshostname
		$data = python $impacket_path\examples\rpcdump.py $hostname | Select-String -Pattern '(MS-RPRN|MS-PAR)'
		if ($data){ 
			Write-Host -ForegroundColor Red "[-] Printspooler enabled on $name"
			Write-Host "Writing to $file"
			echo $name | Add-Content $file
			$data | Add-Content $file
			echo " " | Add-Content $file
		}
		else {
			Write-Host -ForegroundColor DarkGreen "[+] Printspooler disabled on $name"
		}
	}
	Write-Host " "
}

Function Invoke-ADCheckExchange {
<#
.SYNOPSIS
Author: Jony Schats - 0xjs
Required Dependencies: None 
Optional Dependencies: None

.DESCRIPTION
Checks if Exchange is installed within the domain and if there is an Exchange Server. (System part of Exchange Trusted Subsystem)

.PARAMETER Domain
Specifies the domain to use for the query and creating outputdirectory.

.PARAMETER Server
Specifies an Active Directory server IP to bind to, e.g. 10.0.0.1

.PARAMETER User
Specifies the username to use for the query.

.PARAMETER Password
Specifies the Password in combination with the username to use for the query.

.PARAMETER OutputDirectory
Specifies the path to use for the output directory, defaults to the current directory.

.EXAMPLE
Invoke-ADCheckExchange -Domain 'contoso.com' -Server 'dc1.contoso.com' -User '0xjs' -Password 'Password01!'
#>

	#Parameters
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory=$true,HelpMessage="Enter a domain name here, e.g. contoso.com")]
		[ValidateNotNullOrEmpty()]
		[string]$Domain,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter a IP of a domain controller here, e.g. 10.0.0.1")]
		[ValidateNotNullOrEmpty()]
		[string]$Server,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter the username to connect with")]
		[ValidateNotNullOrEmpty()]
		[string]$User,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter the password of the user")]
		[ValidateNotNullOrEmpty()]
		[string]$Password,
		
		[Parameter(Mandatory=$false)]
		[ValidateNotNullOrEmpty()]
		[string]$OutputDirectory
	)

	if ($User -ne $Creds.Username) {
		Create-CredentialObject -User $User -Password $Password
	}	

	if ($OutputDirectoryCreated -ne $true) {
		if ($PSBoundParameters['OutputDirectory']) {
			New-OutputDirectory -Domain $Domain -OutputDirectory $OutputDirectory
			}
			else {
				New-OutputDirectory -Domain $Domain
		}
	}
	
	Write-Host "---Checking if exchange is used within the domain---"
	$file = "$data_path\Exchangegroups.txt"
	$data = Get-DomainGroup -Domain $Domain -Server $Server -Credential $Creds | Select-Object samaccountname | Where-Object samaccountname -Match Exchange
	if ($data){ 	
			Write-Host -ForegroundColor Yellow "[+] Groups with *Exchange* in their name exist"
			Write-Host "[W] Writing to $file"
			$data | Out-File $file
			
			$file = "$data_path\Exchangeservers.txt"
			$data = Get-DomainGroupMember "Exchange Trusted Subsystem" -Domain $Domain -Server $Server -Credential $Creds | Get-DomainComputer -Domain $Domain -Server $Server -Credential $Creds | Select-Object samaccountname, lastlogon | Sort-Object -Property lastlogon -Descending
			if ($data){ 	
					Write-Host -ForegroundColor Yellow "[+] Exchange Trusted Subsystem has memberships, please check if there is a running exchange server and manually check for access/open mailboxes with OWA or Mailsniper"
					Write-Host "[W] Writing to $file"
					$data | Out-File $file
				}
				else {
					Write-Host -ForegroundColor DarkGreen "[+] No group Exchange Trusted Subsystem, there probably is no on-prem Exchange Server"
				}
			Write-Host " "
			
		}
		else {
			Write-Host -ForegroundColor DarkGreen "[+] No Exchange groups exist"
		}
	Write-Host " "
}

Function Invoke-ADCheckWebclient {
<#
.SYNOPSIS
Author: Jony Schats - 0xjs
Required Dependencies: Invoke-ADCheckReachableComputers 
Optional Dependencies: None

.DESCRIPTION
Check if the webclient service is running on all reachable computers.

.PARAMETER Domain
Specifies the domain to use for the query and creating outputdirectory.

.PARAMETER Server
Specifies an Active Directory server IP to bind to, e.g. 10.0.0.1

.PARAMETER User
Specifies the username to use for the query.

.PARAMETER Password
Specifies the Password in combination with the username to use for the query.

.PARAMETER OutputDirectory
Specifies the path to use for the output directory, defaults to the current directory.

.EXAMPLE
Invoke-ADCheckWebclient -Domain 'contoso.com' -Server 'dc1.contoso.com' -User '0xjs' -Password 'Password01!'
#>

	#Parameters
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory=$true,HelpMessage="Enter a domain name here, e.g. contoso.com")]
		[ValidateNotNullOrEmpty()]
		[string]$Domain,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter a IP of a domain controller here, e.g. 10.0.0.1")]
		[ValidateNotNullOrEmpty()]
		[string]$Server,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter the username to connect with")]
		[ValidateNotNullOrEmpty()]
		[string]$User,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter the password of the user")]
		[ValidateNotNullOrEmpty()]
		[string]$Password,
		
		[Parameter(Mandatory=$false)]
		[ValidateNotNullOrEmpty()]
		[string]$OutputDirectory
	)

	if ($User -ne $Creds.Username) {
		Create-CredentialObject -User $User -Password $Password
	}	

	if ($OutputDirectoryCreated -ne $true) {
		if ($PSBoundParameters['OutputDirectory']) {
			New-OutputDirectory -Domain $Domain -OutputDirectory $OutputDirectory
			}
			else {
				New-OutputDirectory -Domain $Domain
		}
	}
	
	if (-not(Test-Path -Path $data_path\computers_accessible.txt)) {
		Invoke-ADCheckReachableComputers -Domain $Domain -Server $Server -User $User -Password $Password
	}
	
	Write-Host "---Running crackmapexec against each reachable host enumerating webclient service---"
	Write-Host -ForeGroundColor yellow "[+] Crackmapexec will hang and needs a enter to continue"
	$data = python.exe $CME_Path smb $data_path\computers_accessible.txt -d $Domain -u $User -p $Password -M webdav | Select-String "WebClient Service enabled on"
	
	if ($data){
		# Writing all data to file
		$file = "$data_path\crackmapexec_webdav.txt"
		Write-Host "[W] Writing all data to $file"
		$data = $data -replace '\x1b\[[0-9;]*m'
		$data | Out-File -Encoding utf8 $file	
		Write-Host " "
		
		# Writing hostnames to findings file
		$file = "$findings_path\computers_webdav.txt"
		$count = $data | Measure-Object | Select-Object -expand Count
		Write-Host -ForegroundColor Red "[+] There are $count systems with the webclient service running"
		Write-Host "[W] Writing to $file"
		# Remove the colors from the data
		$data1 = foreach ($line in $data) {$line.split(":",2)[1]}
		$data1 = $data1.Trim() | ? {$_.trim() -ne "" } #Remove spaces and white lines
		$data1 | Out-File -Encoding utf8 $file
		Write-Host " "
	}
	else {
		Write-Host -ForegroundColor DarkGreen "[+] There are no systems with the webclient service running"
	}
}

Function Invoke-ADCheckLDAP {
<#
.SYNOPSIS
Author: Jony Schats - 0xjs
Required Dependencies: Invoke-ADCheckReachableComputers 
Optional Dependencies: None

.DESCRIPTION
Runs LdapRelayScan and checks if LDAP signing and LDAPS binding is required.

.PARAMETER Server
Specifies an Active Directory server IP to bind to, e.g. 10.0.0.1

.PARAMETER Domain
Specifies the domain to use for the query and creating outputdirectory.

.PARAMETER User
Specifies the username to use for the query.

.PARAMETER Password
Specifies the Password in combination with the username to use for the query.

.PARAMETER OutputDirectory
Specifies the path to use for the output directory, defaults to the current directory.

.EXAMPLE
Invoke-ADCheckLDAP -Server 'dc1.contoso.com' -User '0xjs' -Password 'Password01!'
#>

	#Parameters
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory=$true,HelpMessage="Enter a domain name here, e.g. contoso.com")]
		[ValidateNotNullOrEmpty()]
		[string]$Domain,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter a IP of a domain controller here, e.g. 10.0.0.1")]
		[ValidateNotNullOrEmpty()]
		[string]$Server,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter the username to connect with")]
		[ValidateNotNullOrEmpty()]
		[string]$User,
		
		[Parameter(Mandatory=$true,HelpMessage="Enter the password of the user")]
		[ValidateNotNullOrEmpty()]
		[string]$Password,
		
		[Parameter(Mandatory=$false)]
		[ValidateNotNullOrEmpty()]
		[string]$OutputDirectory
	)

	if ($OutputDirectoryCreated -ne $true) {
		if ($PSBoundParameters['OutputDirectory']) {
			New-OutputDirectory -Domain $Domain -OutputDirectory $OutputDirectory
			}
			else {
				New-OutputDirectory -Domain $Domain
		}
	}
	
	Write-Host "---Running LdapRelayScan---"
	$data = python.exe $LdapRelayScan_Path -m BOTH -dc-ip $Server -u $User -p $Password 2>null
	$file = "$data_path\domaincontrollers_ldaprelayscan.txt"
	Write-Host "[W] Writing to $file"
	$data | Out-File -Encoding utf8 $file
	Write-Host " "
	
	Write-Host "---Checking for LDAP signing---"
	if ($data -Match "SERVER SIGNING REQUIREMENTS NOT ENFORCED!"){
		$file = "$findings_path\domaincontrollers_no_ldap_signing.txt"
		Write-Host -ForegroundColor Red "[+] One or more domain controller(s) doesn't require LDAP signing"
		Write-Host "[W] Writing to $file"
		$data | Out-File -Encoding utf8 $file
	}
	elseif ($data -Match "server enforcing signing requirements") {
		Write-Host -ForegroundColor DarkGreen "[+] The domain controller(s) enforces LDAP signing"
	}
	else {
		Write-Hoost -ForeGroundColor Yellow "[-] Something went wrong please manually check"
	}
	Write-Host " "
	
	Write-Host "---Checking for LDAPS binding---"
	if ($data -Match 'CHANNEL BINDING SET TO "NEVER"! PARTY TIME!'){
		$file = "$findings_path\domaincontrollers_no_ldaps_binding.txt"
		Write-Host -ForegroundColor Red "[+] One or more domain controller(s) doesn't require LDAPS binding"
		Write-Host "[W] Writing to $file"
		$data | Out-File -Encoding utf8 $file
	}
	elseif ($data -Match 'binding set to "required", no fun allowed') {
		$file = "$data_path\domaincontrollers_ldaprelayscan.txt"
		Write-Host -ForegroundColor DarkGreen "[+] The domain controller(s) enforces LDAPS binding"
	}
	elseif ($data -Match 'Unexpected error during LDAPS handshake') {
		Write-Host -ForegroundColor Yellow "[-] LDAPS not (properly) configured"
	}
	else {
		Write-Hoost -ForeGroundColor Yellow "[-] Something went wrong please manually check"
	}
	Write-Host " "
}

