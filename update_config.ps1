$configPath = "C:\Users\sanja\.gemini\config\mcp_config.json"
$json = Get-Content -Raw -Path $configPath | ConvertFrom-Json
$json.mcpServers.StitchMCP.PSObject.Properties.Remove('$typeName')
$json | ConvertTo-Json -Depth 10 | Set-Content -Path $configPath -Encoding utf8
