@{
    RootModule           = 'JevClient.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = '668002d0-1453-446d-90e3-410bb118dc0f'
    Author               = 'Chris Huffman'
    Description          = 'PowerShell client for TypeSafe AI''s jev System One model: Choice, Score and Noul decision questions with calibrated probabilities. Reads the API key from the SecretManagement vault.'
    PowerShellVersion    = '7.0'
    CompatiblePSEditions = @('Core')

    FunctionsToExport    = @(
        'Get-JevApiKey'
        'Invoke-Jev'
        'New-JevChoice'
        'New-JevScore'
        'New-JevNoul'
        'Show-JevAnswer'
        'Show-JevResponse'
        'ConvertTo-JevProbabilityList'
        'Get-JevConfidenceBand'
        'Get-JevProperty'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    PrivateData          = @{
        PSData = @{
            Tags       = @('jev', 'TypeSafe', 'AI', 'decision', 'classification')
            ProjectUri = 'https://github.com/chrishuffman5/jev'
        }
    }
}
