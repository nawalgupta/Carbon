# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Import-CarbonForTest.ps1' -Resolve)
 
$EnvVarName = "CarbonRemoveEnvironmentVar"

function Assert-NoTestEnvironmentVariableAt( $Scope )
{
    $actualValue = [Environment]::GetEnvironmentVariable($EnvVarName, $Scope)
    It ('should remove variable from {0} scope' -f $Scope) {
        $actualValue | Should BeNullOrEmpty
    }
}

function Set-TestEnvironmentVariable($Scope)
{
    $EnvVarValue = [Guid]::NewGuid().ToString()
    [Environment]::SetEnvironmentVariable($EnvVarName, $EnvVarValue, $Scope)
    Set-Item -Path ('env:{0}' -f $EnvVarName) -Value $EnvVarValue
        
    $actualValue = [Environment]::GetEnvironmentVariable($EnvVarName, $Scope) 
    It 'should set variable that will be deleted' {
        $actualValue | Should Be $EnvVarValue
        Test-Path -Path ('env:{0}' -f $EnvVarName) | Should Be $true
    }
        
    return $EnvVarValue
}
   
Describe 'Remove-EnvironmentVariable when removing computer-level variable' {
    Set-TestEnvironmentVariable 'Machine'
    Remove-EnvironmentVariable -Name $EnvVarName -ForComputer
    Assert-NoTestEnvironmentVariableAt -Scope Machine
}
    
Describe 'Remove-EnvironmentVariable when removing user-level variable' {
    Set-TestEnvironmentVariable 'User'
    Remove-EnvironmentVariable -Name $EnvVarName -ForUser
    Assert-NoTestEnvironmentVariableAt -Scope User
}
    
Describe 'Remove-EnvironmentVariable when removing process-level variable' {
    Set-TestEnvironmentVariable 'Process'
    Remove-EnvironmentVariable -Name $EnvVarName -ForProcess
    Assert-NoTestEnvironmentVariableAt -Scope Process
}

Describe 'Remove-EnviromentVariable when removing computer/user-level variables with the Force switch' {

    foreach( $scope in 'Computer','User','Process' )
    {
        Context ('{0}-level' -f $scope) {
            $setScope = $scope
            if( $scope -eq 'Computer' )
            {
                $setScope = 'Machine'
            }
            Set-TestEnvironmentVariable $setScope
            $scopeParam = @{
                                ('For{0}' -f $scope) = $true
                           }
            Remove-EnvironmentVariable -Name $EnvVarName @scopeParam -Force
            Assert-NoTestEnvironmentVariableAt -Scope $setScope
            It 'should remove the variable from the env: drive' {
                Test-Path -Path ('env:{0}' -f $EnvVarName) | Should Be $false
            }
        }
    }
}
    
Describe 'Remove-EnvironmentVariable when variable doesn''t exist' {
    $Global:Error.Clear()
    Remove-EnvironmentVariable -Name "IDoNotExist" -ForComputer
    It 'should not write an error' {
        $Global:Error | Should BeNullOrEmpty
    }
}
    
Describe 'Remove-EnvironmentVariable when using -WhatIf switch' {
    $envVarValue = Set-TestEnvironmentVariable -Scope Process
        
    Remove-EnvironmentVariable -Name $EnvVarName -ForProcess -WhatIf
        
    $actualValue = [Environment]::GetEnvironmentVariable($EnvVarName, 'Process') 
    It 'should not remove variable' {
        $actualValue | Should Not BeNullOrEmpty
        $envVarValue | Should Be $actualValue
    }
}

Describe 'Remove-EnvironmentVariable when removing from all scopes at once' {
    $value = [Guid]::NewGuid().ToString()
    Set-EnvironmentVariable -Name $EnvVarName -Value $value -ForProcess -ForUser -ForComputer
    Remove-EnvironmentVariable -Name $EnvVarName -ForProcess -ForUser -ForComputer
    Assert-NoTestEnvironmentVariableAt -Scope Machine
    Assert-NoTestEnvironmentVariableAt -Scope User
    Assert-NoTestEnvironmentVariableAt -Scope Process
}

Describe 'Remove-EnvironmentVariable when no scopes selected' {
    $Global:Error.Clear()
    Remove-EnvironmentVariable -Name $EnvVarName -ErrorAction SilentlyContinue
    It 'should write an error' {
        $Global:Error | Should Match 'target not specified' 
    }
}
    
Describe 'Remove-EnvironmentVariable when removing variable for another user' {
    #$DebugPreference = 'Continue'
    $value = [Guid]::NewGuid().ToString()
    $credential = New-Credential -UserName 'CarbonTestUser' -Password 'abcd1234!'
    Install-User -Credential $credential
    Set-EnvironmentVariable -Name $EnvVarName -Value $value -ForUser -Credential $credential | Write-Debug
    Remove-EnvironmentVariable -Name $EnvVarName -ForUser -Credential $credential | Write-Debug
    $actualValue = $value
    $actualValue = Invoke-PowerShell -Command ('$env:{0} ; [Environment]::SetEnvironmentVariable("{0}",$null,''User'')' -f $EnvVarName) -Encode -Credential $credential -OutputFormat 'text'
    Write-Debug -Message ($actualValue -join "`n")
    It 'should set that user''s environment variable' {
        $actualValue | Should Be $null
    }
}
Remove-EnvironmentVariable -Name $EnvVarName -ForProcess -ForUser -ForComputer
