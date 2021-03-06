Describe "Set/New/Remove-Service cmdlet tests" -Tags "Feature", "RequireAdminOnWindows" {
    BeforeAll {
        $originalDefaultParameterValues = $PSDefaultParameterValues.Clone()
        if ( -not $IsWindows ) {
            $PSDefaultParameterValues["it:skip"] = $true
        }
    }
    AfterAll {
        $global:PSDefaultParameterValues = $originalDefaultParameterValues
    }

    It "SetServiceCommand can be used as API for '<parameter>' with '<value>'" -TestCases @(
        @{parameter = "Name"        ; value = "bar"},
        @{parameter = "DisplayName" ; value = "hello"},
        @{parameter = "Description" ; value = "hello world"},
        @{parameter = "StartupType" ; value = "Automatic"},
        @{parameter = "StartupType" ; value = "Boot"},
        @{parameter = "StartupType" ; value = "Disabled"},
        @{parameter = "StartupType" ; value = "Manual"},
        @{parameter = "StartupType" ; value = "System"},
        @{parameter = "Status"      ; value = "Running"},
        @{parameter = "Status"      ; value = "Stopped"},
        @{parameter = "Status"      ; value = "Paused"},
        @{parameter = "InputObject" ; script = {Get-Service | Select-Object -First 1}},
        # cmdlet inherits this property, but it's not exposed as parameter so it should be $null
        @{parameter = "Include"     ; value = "foo", "bar" ; expectedNull = $true},
        # cmdlet inherits this property, but it's not exposed as parameter so it should be $null
        @{parameter = "Exclude"     ; value = "foo", "bar" ; expectedNull = $true}
    ) {
        param($parameter, $value, $script, $expectedNull)

        $setServiceCommand = [Microsoft.PowerShell.Commands.SetServiceCommand]::new()
        if ($script -ne $Null) {
            $value = & $script
        }
        $setServiceCommand.$parameter = $value
        if ($expectedNull -eq $true) {
            $setServiceCommand.$parameter | Should BeNullOrEmpty
        }
        else {
            $setServiceCommand.$parameter | Should Be $value
        }
    }

    It "Set-Service parameter validation for invalid values: <script>" -TestCases @(
        @{
            script  = {Set-Service foo -StartupType bar -ErrorAction Stop};
            errorid = "CannotConvertArgumentNoMessage,Microsoft.PowerShell.Commands.SetServiceCommand"
        }
    ) {
        param($script, $errorid)
        { & $script } | ShouldBeErrorId $errorid
    }

    It "Set-Service can change '<parameter>' to '<value>'" -TestCases @(
        @{parameter = "Description"; value = "hello"},
        @{parameter = "DisplayName"; value = "test spooler"},
        @{parameter = "StartupType"; value = "Disabled"},
        @{parameter = "Status"     ; value = "running"     ; expected = "OK"}
    ) {
        param($parameter, $value, $expected)
        $currentService = Get-CimInstance -ClassName Win32_Service -Filter "Name='spooler'"
        $originalStartupType = (Get-Service -Name spooler).StartType
        try {
            $setServiceCommand = [Microsoft.PowerShell.Commands.SetServiceCommand]::new()
            $setServiceCommand.Name = "Spooler"
            $setServiceCommand.$parameter = $value
            $setServiceCommand.Invoke()
            $updatedService = Get-CimInstance -ClassName Win32_Service -Filter "Name='spooler'"
            if ($expected -eq $null) {
                $expected = $value
            }
            if ($parameter -eq "StartupType") {
                $updatedService.StartMode | Should Be $expected
            }
            else {
                $updatedService.$parameter | Should Be $expected
            }
        }
        finally {
            if ($parameter -eq "StartupType") {
                $setServiceCommand.StartupType = $originalStartupType
            }
            else {
                $setServiceCommand.$parameter = $currentService.$parameter
            }
            $setServiceCommand.Invoke()
            $updatedService = Get-CimInstance -ClassName Win32_Service -Filter "Name='spooler'"
            $updatedService.$parameter | Should Be $currentService.$parameter
        }
    }

    It "NewServiceCommand can be used as API for '<parameter>' with '<value>'" -TestCases @(
        @{parameter = "Name"           ; value = "bar"},
        @{parameter = "BinaryPathName" ; value = "hello"},
        @{parameter = "DisplayName"    ; value = "hello world"},
        @{parameter = "Description"    ; value = "this is a test"},
        @{parameter = "StartupType"    ; value = "Automatic"},
        @{parameter = "StartupType"    ; value = "Boot"},
        @{parameter = "StartupType"    ; value = "Disabled"},
        @{parameter = "StartupType"    ; value = "Manual"},
        @{parameter = "StartupType"    ; value = "System"},
        @{parameter = "Credential"     ; value = (
                [System.Management.Automation.PSCredential]::new("username",
                    #[SuppressMessage("Microsoft.Security", "CS002:SecretInNextLine", Justification="Demo/doc/test secret.")]
                    (ConvertTo-SecureString "PlainTextPassword" -AsPlainText -Force)))
        }
        @{parameter = "DependsOn"      ; value = "foo", "bar"}
    ) {
        param($parameter, $value)

        $newServiceCommand = [Microsoft.PowerShell.Commands.NewServiceCommand]::new()
        $newServiceCommand.$parameter = $value
        $newServiceCommand.$parameter | Should Be $value
    }

    It "Set-Service can change credentials of a service" {
        try {
            $startUsername = "user1"
            $endUsername = "user2"
            $testPass = "Secret123!"
            $servicename = "testsetcredential"
            net user $startUsername $testPass /add > $null
            net user $endUsername $testPass /add > $null
            $password = ConvertTo-SecureString $testPass -AsPlainText -Force
            $creds = [pscredential]::new(".\$startUsername", $password)
            $parameters = @{
                Name           = $servicename;
                BinaryPathName = "$PSHOME\powershell.exe";
                StartupType    = "Manual";
                Credential     = $creds
            }
            $service = New-Service @parameters
            $service | Should Not BeNullOrEmpty
            $service = Get-CimInstance Win32_Service -Filter "name='$servicename'"
            $service.StartName | Should BeExactly $creds.UserName

            $creds = [pscredential]::new(".\$endUsername", $password)
            Set-Service -Name $servicename -Credential $creds
            $service = Get-CimInstance Win32_Service -Filter "name='$servicename'"
            $service.StartName | Should BeExactly $creds.UserName
        }
        finally {
            Get-CimInstance Win32_Service -Filter "name='$servicename'" | Remove-CimInstance -ErrorAction SilentlyContinue
            net user $startUsername /delete > $null
            net user $endUsername /delete > $null
        }
    }

    It "New-Service can create a new service called '<name>'" -TestCases @(
        @{name = "testautomatic"; startupType = "Automatic"; description = "foo" ; displayname = "one"},
        @{name = "testmanual"   ; startupType = "Manual"   ; description = "bar" ; displayname = "two"},
        @{name = "testdisabled" ; startupType = "Disabled" ; description = $null ; displayname = $null}
    ) {
        param($name, $startupType, $description, $displayname)
        try {
            $parameters = @{
                Name           = $name;
                BinaryPathName = "$PSHOME\powershell.exe";
                StartupType    = $startupType;
            }
            if ($description) {
                $parameters += @{description = $description}
            }
            if ($displayname) {
                $parameters += @{displayname = $displayname}
            }
            $service = New-Service @parameters
            $service | Should Not BeNullOrEmpty
            $service = Get-CimInstance Win32_Service -Filter "name='$name'"
            $service | Should Not BeNullOrEmpty
            $service.Name | Should Be $name
            $service.Description | Should Be $description
            $expectedStartup = $(
                switch ($startupType) {
                    "Automatic" {"Auto"}
                    "Manual" {"Manual"}
                    "Disabled" {"Disabled"}
                    default { throw "Unsupported StartupType in TestCases" }
                }
            )
            $service.StartMode | Should Be $expectedStartup
            if ($displayname -eq $null) {
                $service.DisplayName | Should Be $name
            }
            else {
                $service.DisplayName | Should Be $displayname
            }
        }
        finally {
            $service = Get-CimInstance Win32_Service -Filter "name='$name'"
            if ($service -ne $null) {
                $service | Remove-CimInstance
            }
        }
    }

    It "Remove-Service can remove a service" {
        try {
            $servicename = "testremoveservice"
            $parameters = @{
                Name           = $servicename;
                BinaryPathName = "$PSHOME\powershell.exe"
            }
            $service = New-Service @parameters
            $service | Should Not BeNullOrEmpty
            Remove-Service -Name $servicename
            $service = Get-Service -Name $servicename -ErrorAction SilentlyContinue
            $service | Should BeNullOrEmpty
        }
        finally {
            Get-CimInstance Win32_Service -Filter "name='$servicename'" | Remove-CimInstance -ErrorAction SilentlyContinue
        }
    }

    It "Remove-Service can accept a ServiceController as pipeline input" {
        try {
            $servicename = "testremoveservice"
            $parameters = @{
                Name           = $servicename;
                BinaryPathName = "$PSHOME\powershell.exe"
            }
            $service = New-Service @parameters
            $service | Should Not BeNullOrEmpty
            Get-Service -Name $servicename | Remove-Service
            $service = Get-Service -Name $servicename -ErrorAction SilentlyContinue
            $service | Should BeNullOrEmpty
        }
        finally {
            Get-CimInstance Win32_Service -Filter "name='$servicename'" | Remove-CimInstance -ErrorAction SilentlyContinue
        }
    }

    It "Remove-Service cannot accept a service that does not exist" {
        { Remove-Service -Name "testremoveservice" -ErrorAction 'Stop' } | ShouldBeErrorId "InvalidOperationException,Microsoft.PowerShell.Commands.RemoveServiceCommand"
    }

    It "Set-Service can accept a ServiceController as pipeline input" {
        try {
            $servicename = "testsetservice"
            $newdisplayname = "newdisplayname"
            $parameters = @{
                Name           = $servicename;
                BinaryPathName = "$PSHOME\powershell.exe"
            }
            $service = New-Service @parameters
            $service | Should Not BeNullOrEmpty
            Get-Service -Name $servicename | Set-Service -DisplayName $newdisplayname
            $service = Get-Service -Name $servicename
            $service.DisplayName | Should BeExactly $newdisplayname
        }
        finally {
            Get-CimInstance Win32_Service -Filter "name='$servicename'" | Remove-CimInstance -ErrorAction SilentlyContinue
        }
    }

    It "Set-Service can accept a ServiceController as positional input" {
        try {
            $servicename = "testsetservice"
            $newdisplayname = "newdisplayname"
            $parameters = @{
                Name           = $servicename;
                BinaryPathName = "$PSHOME\powershell.exe"
            }
            $service = New-Service @parameters
            $service | Should Not BeNullOrEmpty
            $script = { Set-Service $service -DisplayName $newdisplayname }
            { & $script } | Should Not Throw
            $service = Get-Service -Name $servicename
            $service.DisplayName | Should BeExactly $newdisplayname
        }
        finally {
            Get-CimInstance Win32_Service -Filter "name='$servicename'" | Remove-CimInstance -ErrorAction SilentlyContinue
        }
    }

    It "Using bad parameters will fail for '<name>' where '<parameter>' = '<value>'" -TestCases @(
        @{cmdlet="New-Service"; name = 'credtest'    ; parameter = "Credential" ; value = (
            [System.Management.Automation.PSCredential]::new("username",
            #[SuppressMessage("Microsoft.Security", "CS002:SecretInNextLine", Justification="Demo/doc/test secret.")]
            (ConvertTo-SecureString "PlainTextPassword" -AsPlainText -Force)));
            errorid = "CouldNotNewService,Microsoft.PowerShell.Commands.NewServiceCommand"},
        @{cmdlet="New-Service"; name = 'badstarttype'; parameter = "StartupType"; value = "System";
            errorid = "CouldNotNewService,Microsoft.PowerShell.Commands.NewServiceCommand"},
        @{cmdlet="New-Service"; name = 'winmgmt'     ; parameter = "DisplayName"; value = "foo";
            errorid = "CouldNotNewService,Microsoft.PowerShell.Commands.NewServiceCommand"},
        @{cmdlet="Set-Service"; name = 'winmgmt'     ; parameter = "StartupType"; value = "Boot";
            errorid = "CouldNotSetService,Microsoft.PowerShell.Commands.SetServiceCommand"}
    ) {
        param($cmdlet, $name, $parameter, $value, $errorid)
        $parameters = @{$parameter = $value; Name = $name; ErrorAction = "Stop"}
        if ($cmdlet -eq "New-Service") {
            $parameters += @{Binary = "$PSHOME\powershell.exe"};
        }
        { & $cmdlet @parameters } | ShouldBeErrorId $errorid
    }
}
