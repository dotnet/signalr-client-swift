using IntegrationTest.Hubs;
#if USE_AZURE_SIGNALR
using Microsoft.Azure.SignalR;
#endif

var builder = WebApplication.CreateBuilder(args);
builder.Services
    .AddSignalR()
#if USE_AZURE_SIGNALR
    .AddAzureSignalR()
#endif
    .AddMessagePackProtocol();

#if USE_AZURE_SIGNALR
builder.Services.AddControllers();
#endif

var app = builder.Build();

app.UseRouting();
app.MapHub<TestHub>("/test");

app.Run();