# Integration Test Server
A SignalR server for test purpose, supports acting as either a self-hosted SignalR server or an app server for Azure SignalR Service.

# Usage
1. Used as a self-hosted signalr server
```bash
dotnet run
```

2. Used as an app server for Azure SignalR
```bash
dotnet user-secrets set Azure:SignalR:ConnectionString "<connection-string>"
dotnet run -p:DefineConstants="USE_AZURE_SIGNALR"
```