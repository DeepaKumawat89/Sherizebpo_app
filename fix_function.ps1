$filePath = 'D:\BPO\human_bpo\functions\earnings\approveSubmission.js'
$content = [System.IO.File]::ReadAllText($filePath)
$content = $content -replace 'onCall\(async \(request\)', 'onCall(async (data, context)'
$content = $content -replace 'submissionId, adminId \} = request\.data \|\| \{\}', 'submissionId, adminId } = data || {}'
$content = $content -replace 'if \(!request\.auth\)', 'if (!context.auth)'
$content = $content -replace 'request\.auth\.uid', 'context.auth.uid'
[System.IO.File]::WriteAllText($filePath, $content)
Write-Host 'Fix applied successfully'
